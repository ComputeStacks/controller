require "test_helper"
require "minitest/mock"
require "rake"

##
# `networks:audit_orphans` is how production finds the docker networks that are holding a
# live row's subnet under a dead name, so the properties under test are the ones an
# operator's judgement rests on:
#
#   * a docker network whose id label points at a row now carrying a DIFFERENT name is class
#     (a) -- the 403-Forbidden-on-create cause;
#   * a label pointing at no row at all is class (b);
#   * a name that matches its row, where the row has no project, is class (c);
#   * anything with no label of ours is class (d) and is NEVER removed, whatever REMOVE says;
#   * removal is gated on THREE signals, any of which blocks: docker's attached endpoints,
#     every container on the node including STOPPED ones (a stopped container has no
#     endpoint, so docker reports zero attachments and removes the network happily -- and
#     that container can then never start), and, for class (c), the addresses the controller
#     has handed out on the network. Anything that could not be read is ignorance, not
#     emptiness, and blocks too;
#   * a row missing from its node is class (e), and only for regions where every node
#     answered -- an unreachable node means "no data", not "not there".
#
# The classification lives in `NetworkOrphanAudit::Auditor` behind three injection points
# (`nodes:`, `network_lister:`, `container_fetcher:`), so none of this needs a docker daemon.
class NetworkOrphanAuditTest < ActiveSupport::TestCase
  # The shape `Docker::Network.all` yields: anything responding to #info and #remove.
  class FakeNetwork
    attr_reader :info, :removals

    def initialize(name:, subnet: "10.0.0.0/28", labels: {})
      @info = {
        "Name" => name,
        "Labels" => labels,
        "IPAM" => {"Config" => [{"Subnet" => subnet}]}
      }
      @removals = 0
    end

    def remove
      @removals += 1
      nil
    end
  end

  # The shape `Docker::Container.all({all: true})` yields, for the stopped-container index.
  class FakeContainer
    attr_reader :info

    def initialize(name, networks = [])
      @info = {
        "Names" => ["/#{name}"],
        "NetworkSettings" => {"Networks" => networks.to_h { |n| [n, {}] }}
      }
    end
  end

  # See the volume audit test: load_tasks APPENDS an action to every task each time it runs.
  def self.load_tasks_once
    Rails.application.load_tasks unless Rake::Task.task_defined?("networks:audit_orphans")
  end

  setup do
    self.class.load_tasks_once
    @node = nodes(:testone)
    @row = networks(:net_gen_1)
    @out = StringIO.new
  end

  def labelled(network, name:, subnet: nil)
    FakeNetwork.new(
      name: name,
      subnet: subnet || network.subnet.to_s,
      labels: {"com.computestacks.network_id" => network.id.to_s}
    )
  end

  ##
  # @param listed [Array<FakeNetwork>] the networks the node reports
  # @param attached [Hash] docker network name => attached endpoints hash (or nil for gone)
  # @param containers [Array<FakeContainer>] every container on the node, stopped included
  def audit(listed:, attached: {}, containers: [], remove: false, nodes: nil,
    container_lister: nil)
    NetworkOrphanAudit::Auditor.new(
      out: @out,
      remove: remove,
      nodes: nodes || [@node],
      network_lister: ->(_node) { listed },
      container_fetcher: ->(_node, name) { attached.fetch(name, {}) },
      container_lister: container_lister || ->(_node) { containers }
    ).perform
  end

  test "a docker network under a name its row no longer carries is a renamed orphan" do
    orphan = labelled(@row, name: "netpreviousproject")

    auditor = audit(listed: [orphan])

    assert_equal 1, auditor.renamed.size
    candidate = auditor.renamed.first
    assert_equal "netpreviousproject", candidate.observed.name
    assert_equal @row.id, candidate.row.id
    assert candidate.removable?
    assert_empty auditor.unknown
    assert_empty auditor.unallocated
  end

  test "a label pointing at no row is an unknown orphan" do
    ghost = FakeNetwork.new(
      name: "netlongdeleted",
      labels: {"com.computestacks.network_id" => "999999999"}
    )

    auditor = audit(listed: [ghost])

    assert_equal 1, auditor.unknown.size
    assert_equal "netlongdeleted", auditor.unknown.first.observed.name
    assert_empty auditor.renamed
  end

  test "a matching name whose row has no project is unallocated" do
    @row.update! deployment: nil
    matching = labelled(@row, name: @row.name)

    auditor = audit(listed: [matching])

    assert_equal 1, auditor.unallocated.size
    assert_empty auditor.renamed
  end

  test "a matching name whose row has a project is not reported at all" do
    @row.update! deployment: deployments(:project_test)
    matching = labelled(@row, name: @row.reload.name)

    auditor = audit(listed: [matching])

    assert_empty auditor.renamed
    assert_empty auditor.unknown
    assert_empty auditor.unallocated
  end

  test "networks with none of our labels are reported separately and never removed" do
    stranger = FakeNetwork.new(name: "bridge", subnet: "172.17.0.0/16")

    auditor = audit(listed: [stranger], remove: true)

    assert_equal 1, auditor.unlabelled.size
    assert_equal 0, stranger.removals
    assert_empty auditor.removed
  end

  # --- removal gating -----------------------------------------------------------------

  test "REMOVE deletes an orphan with no containers attached" do
    orphan = labelled(@row, name: "netpreviousproject")

    auditor = audit(listed: [orphan], attached: {"netpreviousproject" => {}}, remove: true)

    assert_equal 1, orphan.removals
    assert_equal 1, auditor.removed.size
  end

  test "an orphan with containers attached is reported and left alone even under REMOVE" do
    orphan = labelled(@row, name: "netpreviousproject")
    live = {"netpreviousproject" => {"deadbeef" => {"Name" => "someones-container"}}}

    auditor = audit(listed: [orphan], attached: live, remove: true)

    assert_equal 0, orphan.removals, "a network with endpoints on it is live, whatever the database says"
    assert_empty auditor.removed
    assert_equal 1, auditor.renamed.size
  end

  # nil is "we could not find out", which must never be treated as "nothing is attached".
  test "an orphan whose attachment could not be established is not removed" do
    orphan = labelled(@row, name: "netpreviousproject")

    auditor = audit(listed: [orphan], attached: {"netpreviousproject" => nil}, remove: true)

    assert_equal 0, orphan.removals
    assert_empty auditor.removed
  end

  test "without REMOVE nothing is deleted" do
    orphan = labelled(@row, name: "netpreviousproject")

    auditor = audit(listed: [orphan], attached: {"netpreviousproject" => {}})

    assert_equal 0, orphan.removals
    assert_empty auditor.removed
    assert_match "Re-run with REMOVE=1", @out.string
  end

  test "the database row is not modified by a removal" do
    orphan = labelled(@row, name: "netpreviousproject")

    before = [@row.active, @row.deployment_id]

    audit(listed: [orphan], attached: {"netpreviousproject" => {}}, remove: true)

    @row.reload
    assert_equal before, [@row.active, @row.deployment_id]
  end

  # --- the mirror image ---------------------------------------------------------------

  test "a row that claims to be on a node and is not is reported as missing" do
    @row.update! active: true, deployment: nil

    auditor = audit(listed: [])

    missing_ids = auditor.missing.map { |(row, _)| row.id }
    assert_includes missing_ids, @row.id
  end

  test "a row present on the node is not reported as missing" do
    @row.update! active: true, deployment: nil
    present = labelled(@row, name: @row.reload.name)

    auditor = audit(listed: [present])

    missing_ids = auditor.missing.map { |(row, _)| row.id }
    assert_not_includes missing_ids, @row.id
  end

  # A node that could not be read means no data about its region. Reporting its rows as
  # missing would send an operator re-provisioning networks that are perfectly fine.
  test "a node that errors during the sweep excludes its region from the missing check" do
    @row.update! active: true, deployment: nil

    auditor = NetworkOrphanAudit::Auditor.new(
      out: @out,
      nodes: [@node],
      network_lister: ->(_node) { raise "connection refused" },
      container_fetcher: ->(_node, _name) { {} }
    ).perform

    assert_empty auditor.missing
    assert_match "its region's rows are not audited", @out.string
  end

  test "a region with an unswept node is excluded from the missing check" do
    @row.update! active: true, deployment: nil
    other = Node.create!(
      label: "test02", hostname: "test02", public_ip: "127.0.0.2", primary_ip: "127.0.0.2",
      region: regions(:regionone), active: true
    )

    # Only @node is swept; `other` is in the same region and was not.
    auditor = audit(listed: [], nodes: [@node])

    assert_empty auditor.missing
    assert_not_nil other.id
  end

  # THE gate that matters after a node reboot, which is exactly when an operator reaches for
  # this task. A stopped container holds no endpoint, so docker reports zero attachments and
  # `docker network rm` succeeds -- and that container can then never start again.
  test "a stopped container referencing the network blocks removal" do
    orphan = labelled(@row, name: "netpreviousproject")
    stopped = FakeContainer.new("someones-stopped-container", ["netpreviousproject"])

    auditor = audit(listed: [orphan], attached: {"netpreviousproject" => {}},
      containers: [stopped], remove: true)

    assert_equal 0, orphan.removals
    assert_empty auditor.removed
    assert_match "including stopped ones", auditor.renamed.first.blocker
  end

  test "a container on some other network does not block removal" do
    orphan = labelled(@row, name: "netpreviousproject")
    elsewhere = FakeContainer.new("unrelated", ["netsomethingelse"])

    auditor = audit(listed: [orphan], attached: {"netpreviousproject" => {}},
      containers: [elsewhere], remove: true)

    assert_equal 1, orphan.removals
    assert_equal 1, auditor.removed.size
  end

  # A container list that will not read is ignorance about the whole node.
  test "a node whose container list cannot be read has nothing removed" do
    orphan = labelled(@row, name: "netpreviousproject")

    auditor = audit(listed: [orphan], attached: {"netpreviousproject" => {}}, remove: true,
      container_lister: ->(_node) { raise "connection refused" })

    assert_equal 0, orphan.removals
    assert_empty auditor.removed
    assert_match "container list could not be read", auditor.renamed.first.blocker
    assert_match "cannot be established", @out.string
  end

  # Class (c) has a second, database-side signal the node cannot give us: the addresses the
  # controller has handed out on this network. Non-empty means containers are configured to
  # use it whatever docker currently reports.
  test "addresses allocated on an unallocated network block its removal" do
    @row.update! deployment: nil
    @row.addresses.create!(cidr: "#{@row.subnet.to_s.split("/").first.sub(/\d+$/, "5")}/32")
    matching = labelled(@row, name: @row.reload.name)

    auditor = audit(listed: [matching], attached: {@row.name => {}}, remove: true)

    assert_equal 1, auditor.unallocated.size
    assert_equal 0, matching.removals
    assert_match "address(es) allocated", auditor.unallocated.first.blocker
  end

  # ... and the same signal must NOT block a renamed orphan: those addresses belong to
  # whichever project holds the row now, not to the copy stranded on the node.
  test "addresses on a reallocated row do not block removing the copy stranded under its old name" do
    @row.addresses.create!(cidr: "#{@row.subnet.to_s.split("/").first.sub(/\d+$/, "5")}/32")
    orphan = labelled(@row, name: "netpreviousproject")

    auditor = audit(listed: [orphan], attached: {"netpreviousproject" => {}}, remove: true)

    assert_equal 1, orphan.removals
    assert_equal 1, auditor.removed.size
  end

  test "a negative LIMIT is read as no cap rather than raising" do
    orphan = labelled(@row, name: "netpreviousproject")

    auditor = NetworkOrphanAudit::Auditor.new(
      out: @out, limit: -1, nodes: [@node],
      network_lister: ->(_node) { [orphan] },
      container_fetcher: ->(_node, _name) { {} },
      container_lister: ->(_node) { [] }
    )

    assert_nothing_raised { auditor.perform }
    assert_match "netpreviousproject", @out.string
  end
end
