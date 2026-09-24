require "test_helper"

# Covers Location#allocated_resources -- the figures behind
# GET /api/admin/locations/:id/allocated_resources, and the only operator-visible number
# this change moves.
#
# It used to assume half a core and 512 MB per SFTP container while the node actually
# enforces one core and 1024 MB, so it understated them by half.
class LocationAllocatedResourcesTest < ActiveSupport::TestCase
  # Fixtures: six containers on node testone summing 8 cores / 5120 MB, and two SFTP
  # containers on the same node, all inside region regionone of location testlocation.
  CONTAINER_CPU = 8
  CONTAINER_MEMORY = 5120
  SFTP_QTY = 2

  setup do
    @location = locations(:testlocation)
    @region = regions(:regionone)
  end

  test "counts sftp containers at the size the node enforces" do
    result = @location.allocated_resources

    assert_equal SFTP_QTY, result[:total][:sftp_containers]
    assert_equal CONTAINER_CPU + (SFTP_QTY * Deployment::Sftp::ALLOCATED_CPU),
      result[:total][:cpu]
    assert_equal CONTAINER_MEMORY + (SFTP_QTY * Deployment::Sftp::ALLOCATED_MEMORY),
      result[:total][:memory]
  end

  test "the zone rows sum to the location total" do
    result = @location.allocated_resources
    zones = result[:availability_zones]

    assert_equal result[:total][:cpu], zones.sum { |z| z[:allocated][:cpu] }
    assert_equal result[:total][:memory], zones.sum { |z| z[:allocated][:memory] }
    assert_equal result[:total][:sftp_containers], zones.sum { |z| z[:allocated][:sftp_containers] }
  end

  test "agrees with the figure the placement gate uses for the same zone" do
    # Location#allocated_resources and Region#current_allocated_usage answer the same
    # question for a zone and must not diverge -- they did before, by half an sftp.
    zone = @location.allocated_resources[:availability_zones].find { |z| z[:id] == @region.id }

    assert_equal @region.current_allocated_usage[:cpu][:used], zone[:allocated][:cpu]
    assert_equal @region.current_allocated_usage[:memory][:used], zone[:allocated][:memory]
  end

  test "ignores an sftp container that is awaiting the reaper" do
    before = @location.allocated_resources[:total]

    @region.nodes.first.sftp_containers.first.update!(to_trash: true)

    after = Location.find(@location.id).allocated_resources[:total]
    assert_equal Deployment::Sftp::ALLOCATED_CPU, before[:cpu] - after[:cpu]
    assert_equal Deployment::Sftp::ALLOCATED_MEMORY, before[:memory] - after[:memory]
    assert_equal 1, before[:sftp_containers] - after[:sftp_containers]
  end

  test "attributes an sftp container to the zone whose node runs it" do
    # Not to every zone the project happens to have a service in.
    other = @location.regions.create!(name: "second_zone")
    other_node = other.nodes.create!(active: true, label: "n42", hostname: "n42")
    @region.nodes.first.sftp_containers.first.update!(node: other_node)

    zones = Location.find(@location.id).allocated_resources[:availability_zones]
    moved = zones.find { |z| z[:id] == other.id }
    origin = zones.find { |z| z[:id] == @region.id }

    assert_equal 1, moved[:allocated][:sftp_containers]
    assert_equal SFTP_QTY - 1, origin[:allocated][:sftp_containers]
  end
end
