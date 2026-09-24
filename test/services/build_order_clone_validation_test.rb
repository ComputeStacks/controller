require "test_helper"

##
# Order-build validation for `action: "clone"` volumes.
#
# Both rules exist because the alternative is discovering the problem long after the customer
# has paid: the cross-region check used to live only in the clone worker, and the snapshot
# check read `list_archives` off the *target* volume param (which has no such method), so the
# whole branch 500'd instead of validating anything.
class BuildOrderCloneValidationTest < ActiveSupport::TestCase
  include CloneTestHelpers

  # Build a real order hash, then rewrite the first container's first volume into a clone of
  # `source`. Returns the BuildOrderService, unperformed.
  #
  # @return [BuildOrderService]
  def clone_order(source_csrn:, snapshot: nil)
    session = OrderSession.new users(:admin)
    session.project.name = "Clone Validation"
    session.add_image container_image_image_variants(:wordpress_default)
    session.images.each { |i| i[:package_id] = products(:containersmall).id }
    session.location = locations(:testlocation)
    session.save
    session = OrderSession.new(users(:admin), session.id)
    session.save

    order = session.to_order
    order[:containers].first[:volumes] = [
      order[:containers].first[:volumes].first.merge(
        action: "clone",
        source: source_csrn,
        snapshot: snapshot
      )
    ]

    service = BuildOrderService.new(
      Audit.create!(user: users(:admin), ip_addr: "127.0.0.1", event: "created"),
      order
    )
    service.process_order = false
    service
  end

  test "a clone of a same-region source with no snapshot builds" do
    service = clone_order source_csrn: volumes(:mysql).csrn
    assert service.perform, service.errors.inspect
  end

  test "a clone whose snapshot is missing is a validation error, not a NoMethodError" do
    seed_archives volumes(:mysql), [archive_name("something-else")]

    service = clone_order source_csrn: volumes(:mysql).csrn, snapshot: "bm9wZQ=="

    # The bug this pins: `vol.list_archives` where `vol` is the TARGET — a
    # ContainerImage::VolumeParam, which answers no such method — so this raised
    # NoMethodError and returned a 500 to the API caller instead of an error list.
    refute service.perform
    assert_includes service.errors, "Snapshot not found"
  end

  test "a clone whose snapshot exists on the source volume builds" do
    name = archive_name "keepme"
    seed_archives volumes(:mysql), [name]

    service = clone_order(
      source_csrn: volumes(:mysql).csrn,
      snapshot: Base64.urlsafe_encode64(name)
    )

    assert service.perform, service.errors.inspect
  end

  test "a clone from another availability zone is rejected at submit time" do
    other_region = Region.create!(
      location: locations(:testlocation),
      name: "clone-validation-az",
      volume_backend: "local",
      p_net_size: 28,
      network_driver: "bridge"
    )
    far_volume = Volume.create!(
      label: "faraway",
      user: users(:admin),
      name: SecureRandom.uuid,
      borg_enabled: true,
      enable_sftp: false,
      region: other_region,
      volume_backend: "local",
      deployment: deployments(:project_test)
    )

    service = clone_order source_csrn: far_volume.csrn

    refute service.perform
    assert_includes service.errors, "You may only clone volumes from the same availability zone"
  end

  test "a template csrn as a clone source is rejected rather than raising" do
    template_csrn = ContainerImage::VolumeParam.first&.csrn
    skip "no volume params to point at" if template_csrn.nil?

    service = clone_order source_csrn: template_csrn

    # Csrn.locate resolves this to a ContainerImage::VolumeParam, which answers neither
    # can_view? nor region nor list_archives.
    refute service.perform
    assert(service.errors.any? { |e| e.start_with?("Unknown source volume") }, service.errors.inspect)
  end
end
