require "test_helper"
require "minitest/mock"
require "rake"

##
# `volumes:audit_mounts` is the tool that decides whether production needs a backfill before
# `volumes.awaiting_mount` ships, so the properties under test are the ones an operator's
# judgement rests on:
#
#   * a volume with a map that NO container of its service mounts is class (a) — the set whose
#     borg archives are all empty;
#   * a volume with `template_id` and no map at all is class (b), reported with its phantom
#     "Detached Volume" subscription, never auto-fixed;
#   * duplicate `(container_service_id, mount_path)` maps are surfaced as class (c);
#   * a node that could not be read is class (d) and NEVER class (a). This is the important
#     one: `Node#list_all_containers` rescues everything and returns `[]`, so if silence were
#     read as "not mounted", `FIX=1` would push `backup: false` for every volume on a node
#     with a hiccuping docker API — disabling backups on live customer data;
#   * `FIX=1` flips class (a) only, and does it through `update!` so `after_commit
#     :update_consul!` tells the agent `backup: false` there and then.
#
# The classification logic lives in `VolumeMountAudit::Auditor` inside the rake file, with the
# node sweep behind two injection points (`nodes:` and `container_lister:`), so none of this
# needs a docker daemon.
class VolumeMountAuditTest < ActiveSupport::TestCase
  # The shape `Node#list_all_containers` yields: anything responding to #info with "Names"
  # and "Mounts". Not a docker mock — just the two keys the sweep reads.
  class FakeContainer
    attr_reader :info

    # @param name [String] container name (docker reports it with a leading slash)
    # @param mounts [Array<Array(String, String)>] [volume name, destination] pairs
    def initialize(name, mounts = [])
      @info = {
        "Names" => ["/#{name}"],
        "Mounts" => mounts.map { |(volume_name, path)| {"Name" => volume_name, "Destination" => path} }
      }
    end
  end

  # Guard on the task being defined, not on a per-class flag: Rails.application.load_tasks
  # APPENDS the task body as another action every time it runs, and it defines EVERY task,
  # not just this one. A per-class flag only knows whether THIS class has loaded them, so
  # when another task test class had already loaded them this call appended a second action
  # to every task in the process -- and the next class to invoke one ran its body twice.
  def self.load_tasks_once
    Rails.application.load_tasks unless Rake::Task.task_defined?("volumes:audit_mounts")
  end

  setup do
    self.class.load_tasks_once
    @node = nodes(:testone)
    @mysql_volume = volumes(:mysql)      # owner map on service mysql, container mysql_1
    @nginx_volume = volumes(:nginx_web)  # owner map on service nginx, container nginx_1
    # The audit's candidate set is `where.not(template_id: nil)` and no volume fixture carries
    # one. update_columns, not update! — Volume's `after_commit :update_consul!` would fire a
    # real agent HTTP call during setup.
    @mysql_volume.update_columns(template_id: container_image_volume_params(:mysql_data).id)
    @nginx_volume.update_columns(template_id: container_image_volume_params(:nginx_webroot).id)
  end

  test "a mapped volume that no container mounts is class (a), and a mounted one is fine" do
    auditor, out = audit(containers: {@node.id => container_list})

    assert_equal [@nginx_volume.id], auditor.unmounted.map { |(v, _)| v.id }
    assert_equal [@mysql_volume.id], auditor.mounted.map { |(v, _)| v.id }
    assert_empty auditor.undetermined
    assert_match(/\(a\) MAPPED BUT NOT MOUNTED — 1 volume\(s\)/, out)
    assert_match(/vol #{@nginx_volume.id}\s+"nginx"/, out)
    assert_match(%r{path="/var/www"}, out)
    # borg_enabled is true on the fixture and awaiting_mount is still false, so the report has
    # to say the agent was told to back this empty volume up.
    assert_match(/agent_backup=ON/, out)
    refute_match(/Nothing to do/, out)
  end

  test "a volume with template_id and no map is class (b), with its detached subscription" do
    orphan = Volume.create!(
      label: "retry orphan",
      user: users(:admin),
      region: regions(:regionone),
      template: container_image_volume_params(:custom_files)
    )

    auditor, out = audit(containers: {@node.id => container_list})

    assert_includes auditor.orphans.map(&:id), orphan.id
    refute_includes auditor.unmounted.map { |(v, _)| v.id }, orphan.id
    assert_match(/\(b\) ORPHANS \(template_id, no volume_maps\)/, out)
    assert_match(/vol #{orphan.id}\s+"retry orphan".*template=#{orphan.template_id}.*subscription=/, out)
    # set_detached stamps this on commit, which is what mints the phantom subscription.
    assert_not_nil orphan.reload.detached_at
    assert_match(/NOT auto-fixed/, out)
  end

  ##
  # The unique index on (container_service_id, mount_path) ships in the same release, so the
  # only way to hold a duplicate pair is to drop it for the duration of this test. Postgres DDL
  # is transactional, so the test transaction rolls it back; the ensure block is belt-and-braces
  # for the shared test database.
  test "duplicate (container_service_id, mount_path) maps are class (c)" do
    owner = volume_maps(:mysql_vol_map)
    duplicate_id = nil
    connection = ActiveRecord::Base.connection
    connection.execute("DROP INDEX IF EXISTS index_volume_maps_on_service_and_path")
    begin
      # insert_all: the AR uniqueness validation would refuse this, and that racy validation is
      # exactly why the pair can exist in production in the first place.
      duplicate_id = VolumeMap.insert_all([{
        volume_id: @nginx_volume.id,
        container_service_id: owner.container_service_id,
        mount_path: owner.mount_path,
        mount_ro: false,
        is_owner: false,
        created_at: Time.current,
        updated_at: Time.current
      }]).rows.flatten.first

      auditor, out = audit(containers: {@node.id => container_list})

      assert_equal 1, auditor.duplicates.size
      service_id, mount_path, maps = auditor.duplicates.first
      assert_equal owner.container_service_id, service_id
      assert_equal owner.mount_path, mount_path
      assert_equal [owner.id, duplicate_id].sort, maps.map(&:id).sort
      assert_match(/\(c\) DUPLICATE VOLUME MAPS — 1 \(container_service_id, mount_path\) pair\(s\)/, out)
      assert_match(/map #{owner.id}\s+volume #{owner.volume_id}/, out)
    ensure
      VolumeMap.where(id: duplicate_id).delete_all if duplicate_id
      unless connection.index_name_exists?(:volume_maps, "index_volume_maps_on_service_and_path")
        connection.add_index :volume_maps, %i[container_service_id mount_path], unique: true,
          name: "index_volume_maps_on_service_and_path"
      end
    end
  end

  test "an offline node yields class (d) and never class (a)" do
    auditor, out = audit(nodes: [])

    assert_empty auditor.unmounted
    assert_equal [@mysql_volume.id, @nginx_volume.id].sort, auditor.undetermined.map { |(v, _)| v.id }.sort
    assert_match(/\(d\) UNDETERMINED — 2 volume\(s\)/, out)
    assert_match(/offline or in maintenance/, out)
  end

  ##
  # The false-(a) trap: list_all_containers rescues a dead docker API and returns []. Silence
  # must be read as "no data", not "nothing is mounted".
  test "an online node that reports zero containers yields class (d), not class (a)" do
    auditor, out = audit(containers: {@node.id => []})

    assert_empty auditor.unmounted
    assert_equal 2, auditor.undetermined.size
    assert_match(/reported 0 containers/, out)
    assert_match(/UNDETERMINED, never class \(a\)/, out)
  end

  test "a volume mounted only by a container outside its service is reported, not class (a)" do
    sftp = FakeContainer.new("sftp-project-test", [[@nginx_volume.name, "/mnt/nginx"]])
    auditor, out = audit(containers: {@node.id => container_list + [sftp]})

    assert_empty auditor.unmounted
    assert_equal [@nginx_volume.id], auditor.mounted_elsewhere.map { |(v, _)| v.id }
    assert_match(/MOUNTED BY A CONTAINER THAT IS NOT PART OF THE MAPPED SERVICE/, out)
    assert_match(/container=sftp-project-test at \/mnt\/nginx/, out)
  end

  test "FIX=1 flips only class (a) and pushes backup: false to the agent" do
    orphan = Volume.create!(
      label: "retry orphan",
      user: users(:admin),
      region: regions(:regionone),
      template: container_image_volume_params(:custom_files)
    )
    fake = FakeAgentClient.new
    auditor = nil
    out = nil
    Agent::Client.stub(:for_node, fake) do
      auditor, out = audit(fix: true, containers: {@node.id => container_list})
    end

    assert_equal [@nginx_volume.id], auditor.fixed.map(&:id)
    assert @nginx_volume.reload.awaiting_mount, "class (a) volume should be awaiting_mount"
    refute @mysql_volume.reload.awaiting_mount, "a mounted volume must not be touched"
    refute orphan.reload.awaiting_mount, "class (b) is reported, never fixed"

    push = fake.calls_of(:put_volume).detect { |c| c[2] == @nginx_volume.name }
    assert push, "the update! must push desired-state for the fixed volume"
    assert_equal false, push[3][:backup], "the agent must be told to stop backing this up"
    assert_match(/\[fixed\] vol #{@nginx_volume.id}/, out)
    assert_match(/Left alone: \(b\) 1, \(c\) 0, \(d\) 0/, out)
  end

  test "FIX=1 is a no-op when class (a) is empty" do
    fake = FakeAgentClient.new
    out = nil
    Agent::Client.stub(:for_node, fake) do
      _, out = audit(fix: true, containers: {@node.id => container_list(nginx_mounted: true)})
    end

    assert_match(/FIX=1: nothing to do — no class \(a\) volume needs flagging/, out)
    assert_empty fake.calls_of(:put_volume)
    refute @nginx_volume.reload.awaiting_mount
  end

  test "a truncated listing says so instead of silently capping" do
    _, out = audit(containers: {@node.id => container_list(mysql_mounted: false)}, limit: 1)

    assert_match(/and 1 more not listed \(2 total; re-run with LIMIT=0 to list all\)/, out)
  end

  test "reports nothing to do when every candidate is mounted" do
    _, out = audit(containers: {@node.id => container_list(nginx_mounted: true)})

    assert_match(/Nothing to do/, out)
    assert_match(/ok, mounted                : 2/, out)
  end

  test "the rake task itself runs and reports" do
    task = Rake::Task["volumes:audit_mounts"]
    task.reenable
    # Node.online stubbed empty so the wrapper is exercised without the sweep reaching for a
    # docker daemon (Node#list_all_containers would try DEV_VM_IP and rescue to []).
    out = capture_io { Node.stub(:online, Node.none) { task.invoke } }.first

    assert_match(/volumes:audit_mounts — report only/, out)
    assert_match(/Candidates examined: 2/, out)
  end

  private

  # @return [Array(VolumeMountAudit::Auditor, String)]
  def audit(fix: false, nodes: [@node], containers: {}, limit: 0)
    out = StringIO.new
    auditor = VolumeMountAudit::Auditor.new(
      out: out,
      fix: fix,
      limit: limit,
      nodes: nodes,
      container_lister: ->(node) { containers.fetch(node.id, []) }
    )
    auditor.perform
    [auditor, out.string]
  end

  # The node's container list. By default the mysql service's container carries its bind and the
  # nginx service's does not — i.e. one healthy volume and one casualty of the broken cascade.
  def container_list(mysql_mounted: true, nginx_mounted: false)
    [
      FakeContainer.new(
        deployment_containers(:mysql_1).name,
        mysql_mounted ? [[@mysql_volume.name, "/var/lib/mysql"]] : []
      ),
      FakeContainer.new(
        deployment_containers(:nginx_1).name,
        nginx_mounted ? [[@nginx_volume.name, "/var/www"]] : []
      )
    ]
  end
end
