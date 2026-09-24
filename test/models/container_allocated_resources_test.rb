require "test_helper"

# Covers Deployment::Container.allocated_resources -- the committed cpu/memory figure
# behind BOTH Node#allocated_resources and Region#current_allocated_usage, which sit on
# the customer order path (Region#find_node and Location#next_region respectively).
#
# It replaced a row-by-row walk to each container's subscription and that subscription's
# billing package: 1061 queries and 3.1s for one zone in production.
class ContainerAllocatedResourcesTest < ActiveSupport::TestCase
  # Fixture containers, all on node testone, all in region regionone:
  #
  #   pma_1               1 /  512   NO subscription
  #   wordpress_1         2 / 1536   containerl      (2 / 1536 -- agrees)
  #   wordpress_custom_1  2 / 1536   containerl      (2 / 1536 -- agrees)
  #   mysql_1             1 /  512   containersmall  (0.5 / 256 -- DISAGREES)
  #   nginx_1             1 /  512   containersmall  (0.5 / 256 -- DISAGREES)
  #   user_nginx_1        1 /  512   containersmall  (0.5 / 256 -- DISAGREES)
  EXPECTED_CPU = 8
  EXPECTED_MEMORY = 5120

  setup do
    @node = nodes(:testone)
    @region = regions(:regionone)
  end

  test "sums the containers' own cpu and memory columns" do
    result = Deployment::Container.allocated_resources(@node.containers)

    assert_equal EXPECTED_CPU, result[:cpu]
    assert_equal EXPECTED_MEMORY, result[:memory]
  end

  test "works through a scope that joins container_services" do
    # region.containers is has_many :through :container_services, so the sum runs over a
    # joined relation rather than a plain one. Both tables carry cpu and memory columns,
    # which is why the implementation names the table explicitly -- Rails qualifies a
    # symbol column too, so this is belt and braces rather than the only thing standing
    # between us and an ambiguous-column error.
    result = Deployment::Container.allocated_resources(@region.containers)

    assert_equal EXPECTED_CPU, result[:cpu]
    assert_equal EXPECTED_MEMORY, result[:memory]
  end

  test "counts a container that has no subscription" do
    pma = deployment_containers(:pma_1)
    assert_nil pma.subscription, "fixture no longer models the unsubscribed case"

    with_pma = Deployment::Container.allocated_resources(@node.containers)
    without_pma = Deployment::Container.allocated_resources(
      @node.containers.where.not(id: pma.id)
    )

    # The old region-side walk went container_services -> subscriptions, so this
    # container was invisible to it. Project load balancers and free-toggle images are
    # 503 of 2310 containers in production; they must be counted.
    assert_equal pma.cpu, with_pma[:cpu] - without_pma[:cpu]
    assert_equal pma.memory, with_pma[:memory] - without_pma[:memory]
  end

  test "takes the container's own columns even when they disagree with its package" do
    mysql = deployment_containers(:mysql_1)
    package = mysql.subscription.package

    # Deliberately divergent in the fixtures: the column is the source of truth here,
    # because it is the only figure an unsubscribed container has and production keeps
    # the two in step (verified across all nine zones on 2026-09-04).
    refute_equal package.cpu, mysql.cpu, "fixture no longer models the divergent case"

    result = Deployment::Container.allocated_resources(
      Deployment::Container.where(id: mysql.id)
    )
    assert_equal mysql.cpu, result[:cpu]
    assert_equal mysql.memory, result[:memory]
  end

  test "an empty scope is zero, not nil" do
    result = Deployment::Container.allocated_resources(Deployment::Container.none)

    assert_equal 0, result[:cpu]
    assert_equal 0, result[:memory]
  end

  test "costs two queries regardless of how many containers there are" do
    assert_equal 6, @node.containers.count, "fixture container count changed"

    assert_equal 2, count_queries { Deployment::Container.allocated_resources(@node.containers) }
  end

  # --- SFTP -------------------------------------------------------------------------
  #
  # SFTP containers occupy a node like anything else, but have no cpu/memory columns --
  # Deployment::Sftp's runtime payload hardcodes what it asks Docker for, so the constants
  # are the source. Two fixtures, both on node testone / region regionone.

  SFTP_QTY = 2
  SFTP_CPU = SFTP_QTY * Deployment::Sftp::ALLOCATED_CPU
  SFTP_MEMORY = SFTP_QTY * Deployment::Sftp::ALLOCATED_MEMORY

  test "SFTP containers are counted at what the node enforces for them" do
    assert_equal SFTP_QTY, @node.sftp_containers.count, "fixture sftp count changed"

    result = Deployment::Sftp.allocated_resources(@node.sftp_containers)

    assert_equal SFTP_CPU, result[:cpu]
    assert_equal SFTP_MEMORY, result[:memory]
  end

  test "Node#allocated_resources counts containers AND sftp containers" do
    result = @node.allocated_resources

    assert_equal EXPECTED_CPU + SFTP_CPU, result[:cpu]
    assert_equal EXPECTED_MEMORY + SFTP_MEMORY, result[:memory]
  end

  test "Region#current_allocated_usage counts containers AND sftp containers" do
    usage = @region.current_allocated_usage

    assert_equal EXPECTED_CPU + SFTP_CPU, usage[:cpu][:used]
    assert_equal EXPECTED_MEMORY + SFTP_MEMORY, usage[:memory][:used]
  end

  test "a region counts the sftp containers on its nodes" do
    # Scoped by node_id, not through the region's deployments association: the node the
    # row runs on is whose capacity it consumes.
    moved = @node.sftp_containers.first
    before = @region.current_allocated_usage[:cpu][:used]

    other = regions(:regionone).location.regions.create!(name: "elsewhere")
    moved.update!(node: other.nodes.create!(active: true, label: "n9", hostname: "n9"))

    after = @region.reload.current_allocated_usage[:cpu][:used]
    assert_equal Deployment::Sftp::ALLOCATED_CPU, before - after
  end

  private

  def count_queries
    count = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless /\A(SCHEMA|TRANSACTION)\z/.match?(payload[:name].to_s)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end
end
