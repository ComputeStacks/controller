require "test_helper"
require "minitest/mock"

##
# ProvisionServices::SftpProvisioner and the nodes it cannot find.
#
# #perform returns `errors.empty?`, and on the order path ProcessOrderService#finalize!
# turns that false into its own error, which makes it call fail_process!, which detaches
# the private network of a project whose containers are already built and running. So a
# zone we merely failed to place into must never reach `errors`: it is a warning plus an
# operator-facing event_details row, and the run still succeeds.
#
# The test that matters most here is the region-migration one. Volumes moving from zone A
# to zone B leave the project's only SFTP container behind in A, `regions` derives from
# the volumes so A is never even iterated, and find_node(B) can come back nil. The nil
# used to be pushed into the node list, where it defeated the "we already have one" ladder
# and got the surviving container trashed.
class SftpProvisionerTest < ActiveSupport::TestCase
  setup do
    @event = EventLog.create!(
      locale: "deployment.sftp",
      event_code: "1a2b3c4d5e6f7081",
      status: "pending"
    )
    @project = deployments(:project_test)
    @sftp = deployment_sftp(:project_test_testone)
  end

  # --- C2: a zone that cannot be placed into ----------------------------------------

  test "a region with no available node is a warning, not an error, and the run succeeds" do
    migrate_volumes_to empty_zone

    provisioner = run_provisioner

    assert_empty provisioner.errors, "a placement failure must never reach errors"
    assert_equal 1, provisioner.warnings.count
    assert_match(/Could not place an SFTP container in/, provisioner.warnings.first)
    assert provisioner.result, "a skipped zone must not fail the whole run"
  end

  test "the skipped region is recorded on the event log" do
    zone = empty_zone
    migrate_volumes_to zone

    run_provisioner

    detail = @event.event_details.reload.find { |d|
      d.event_code == ProvisionServices::SftpProvisioner::PLACEMENT_SKIPPED_EVENT_CODE
    }
    refute_nil detail, "the ladder can `return true` before anyone reads `warnings` -- " \
      "the warning has to reach the event log or it is lost"
    assert_match(/#{zone.name}/, detail.data)
  end

  ##
  # THE data-loss test. One project, one SFTP container, and its zone is no longer among
  # the project's volume regions.
  test "the project's only SFTP container survives a region migration it was left out of" do
    migrate_volumes_to empty_zone

    trashed = nil
    provisioner = nil
    trashed = recording_trash { provisioner = run_provisioner }

    assert_empty trashed,
      "the surviving SFTP container is in a zone `regions` no longer mentions; a nil in " \
      "the node list defeats the step-2 ladder and this container gets destroyed"
    assert Deployment::Sftp.exists?(@sftp.id)
    refute @sftp.reload.to_trash
    assert provisioner.result, provisioner.errors.inspect
  end

  test "no new SFTP container is built for a zone that could not be placed" do
    migrate_volumes_to empty_zone

    assert_no_difference -> { Deployment::Sftp.count } do
      run_provisioner
    end
  end

  ##
  # Region#context speaks the vocabulary of the placement algorithm. It is operator-only:
  # an unreachable metrics server reads as `{metric_cpu_cores: 0, requested_cpu: 1.0}`,
  # which would tell a customer their node has no CPUs.
  test "the placement detail goes to the operator and not into the customer's warning" do
    zone = empty_zone
    undersized = zone.nodes.create!(label: "toosmall", hostname: "toosmall", active: true,
      primary_ip: "127.0.0.60", public_ip: "127.0.0.60")
    undersized.update_columns(cpu_cores: 1, memory_mb: 256)
    migrate_volumes_to zone

    provisioner = run_provisioner

    code = ProvisionServices::SftpProvisioner::PLACEMENT_SKIPPED_EVENT_CODE

    # The customer's channel: app/views/event_logs/_show.html.erb renders event_details
    # raw to the project owner. It must carry the plain sentence and nothing else.
    detail = @event.event_details.reload.find { |d| d.event_code == code }
    refute_nil detail, "the customer should be told the container was not created"
    refute_match(/node_system_memory/, detail.data)
    refute_match(/metric_cpu_cores/, detail.data)
    refute_match(/warnings.first/, detail.data)
    assert_equal provisioner.warnings.first, detail.data

    # The operator's channel: SystemEvent is admin-only, and carries the diagnostic.
    system_event = SystemEvent.where(event_code: code).order(:created_at).last
    refute_nil system_event, "the operator should get the placement diagnostic"
    assert_match(/node_system_memory/, system_event.data.to_s)
    refute_match(/node_system_memory/, provisioner.warnings.first)

    assert provisioner.result
  end

  # --- C3: a volume with nowhere to pin ---------------------------------------------

  test "a volume with no node associations warns instead of putting nil in the node list" do
    # Local storage: the container is pinned to the volume's own host, and a volume that
    # has never been attached anywhere has no host to offer.
    orphan = Volume.create!(
      label: "orphaned",
      user: users(:admin),
      name: SecureRandom.uuid,
      borg_enabled: false,
      enable_sftp: true,
      region: regions(:regionone),
      volume_backend: "local",
      deployment: @project
    )
    deployment_container_services(:nginx).volume_maps.create!(
      volume: orphan, mount_ro: false, mount_path: "/mnt/orphan", is_owner: true
    )
    refute @project.reload.has_clustered_storage?, "this test needs the local-storage branch"

    trashed = nil
    provisioner = nil
    trashed = recording_trash { provisioner = run_provisioner }

    assert provisioner.result, provisioner.errors.inspect
    assert_equal 1, provisioner.warnings.count
    assert_match(/orphaned/, provisioner.warnings.first)
    # A nil in the list reaches step 5, where LoadBalancer.find_by_node(nil) is nil and
    # the run fails on a node that never existed.
    assert_empty provisioner.errors
    assert_empty trashed
  end

  # --- C1 must not break the deliberate empty list ----------------------------------

  test "skip_ssh still trashes every SFTP container" do
    @project.update_columns(skip_ssh: true)

    trashed = nil
    provisioner = nil
    trashed = recording_trash { provisioner = run_provisioner }

    assert provisioner.result, provisioner.errors.inspect
    assert_equal [@sftp], trashed,
      "emptying the node list is how skip_ssh removes containers -- the compact! and the " \
      "placement guards must not disturb it"
  end

  # --- C5: the ladder's own nil ------------------------------------------------------

  test "the step-2 ladder fails cleanly when the project's last available node disappears" do
    project = bare_project
    # Exactly the race the guard exists for: available at the top of #perform, gone by the
    # time the ladder asks for one. Second and later reads see an empty set.
    remaining = Node.where(id: nodes(:testone).id)
    project.define_singleton_method(:nodes) do
      current = remaining
      remaining = Node.none
      current
    end

    provisioner = ProvisionServices::SftpProvisioner.new(project, @event)
    result = nil
    assert_nothing_raised { result = provisioner.perform }

    refute result, "nothing can be placed at all -- this one IS an error"
    assert_includes provisioner.errors, "This project has no available nodes!"
  end

  private

  ##
  # A zone with no nodes in it, so Region#find_node returns nil straight away.
  def empty_zone
    @empty_zone ||= begin
      zone = Region.create!(
        location: locations(:testlocation),
        name: "migrated-az",
        volume_backend: "local",
        p_net_size: 28,
        network_driver: "bridge"
      )
      # Created local and flipped afterwards: the nfs backend validates a remote host we
      # do not need here, and nothing under test reads it.
      zone.update_columns(volume_backend: "nfs")
      zone.reload
    end
  end

  ##
  # Reproduce RegionMigratorService#migrate_volumes: the volumes move, the containers --
  # and the SFTP container -- do not. `regions` derives from the volumes, so the zone the
  # SFTP container actually lives in is never iterated.
  #
  # regionone is flipped to a clustered backend so Deployment#has_clustered_storage? sends
  # us down the branch that calls find_node at all.
  def migrate_volumes_to(zone)
    regions(:regionone).update_columns(volume_backend: "nfs")
    @project.volumes.each { |v| v.update_columns(region_id: zone.id) }
    @project.reload
    assert @project.has_clustered_storage?, "this test needs the clustered branch"
    assert_equal [zone], @project.volumes.select(:region_id).distinct.map { |i| i.region }
    assert_equal 1, @project.sftp_containers.active.count
    assert_equal regions(:regionone), @sftp.node.region
  end

  # @return [ProvisionServices::SftpProvisioner] with #result carrying #perform's answer
  def run_provisioner(project = @project)
    provisioner = ProvisionServices::SftpProvisioner.new(project, @event)
    result = nil
    assert_nothing_raised { result = provisioner.perform }
    provisioner.define_singleton_method(:result) { result }
    provisioner
  end

  ##
  # Collect the containers handed to TrashContainer rather than trying to talk to a node.
  # @return [Array] the containers it was asked to destroy
  def recording_trash
    trashed = []
    fake = Object.new
    def fake.perform
      true
    end
    ContainerServices::TrashContainer.stub(:new, ->(container, _event) {
      trashed << container
      fake
    }) do
      yield
    end
    trashed
  end

  ##
  # A project with one container on the fixture node, no SFTP containers and no
  # sftp-enabled volumes -- so step 1 produces an empty node list.
  def bare_project
    project = Deployment.create!(user: users(:admin), name: "bare_#{SecureRandom.hex(4)}")
    service = project.services.create!(
      name: "svc#{SecureRandom.hex(3)}",
      container_image: ContainerImage.first,
      region: regions(:regionone)
    )
    service.containers.create!(
      name: "c#{SecureRandom.hex(3)}",
      node: nodes(:testone),
      cpu: 0.1,
      memory: 128
    )
    project.reload
  end
end
