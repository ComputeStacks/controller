require "test_helper"

##
# Node#maintenance is a STORED GENERATED column:
#   maintenance_requested OR COALESCE(jsonb_typeof(maintenance_holds -> 'local') = 'object', false)
#
# The COALESCE is load-bearing. Without it `'{}' -> 'local'` is SQL NULL, `false OR NULL`
# is NULL, and the node silently drops out of online / available / offline at once. So
# these assert_equal false rather than refute: refute would pass on nil.
class NodeMaintenanceTest < ActiveSupport::TestCase
  setup do
    @node = nodes(:testone)
    @node.update_columns(active: true, disconnected: false, maintenance_requested: false, maintenance_holds: {})
  end

  def set_state(requested: false, holds: {})
    @node.update_columns(maintenance_requested: requested, maintenance_holds: holds)
    @node.reload
  end

  def raw_maintenance
    Node.connection.select_value("SELECT maintenance FROM nodes WHERE id = #{@node.id}")
  end

  NOT_IN_MAINTENANCE = {
    "empty holds" => {},
    "local: null" => {"local" => nil},
    "local key missing" => {"controller" => {"since" => "2026-10-07T00:00:00Z", "reason" => "x", "gen" => 1}, "paused" => true}
  }.freeze

  NOT_IN_MAINTENANCE.each do |name, holds|
    test "generated column is false (not NULL) for #{name}" do
      set_state(holds: holds)
      assert_equal false, raw_maintenance
      assert_equal false, @node.maintenance
      assert @node.online?
      assert_includes Node.online, @node
      assert_includes Node.available, @node
      refute_includes Node.offline, @node
    end
  end

  test "generated column is true when the controller requests maintenance" do
    set_state(requested: true)
    assert_equal true, raw_maintenance
    assert_equal true, @node.maintenance
    refute @node.online?
    refute_includes Node.online, @node
    refute_includes Node.available, @node
    assert_includes Node.offline, @node
  end

  test "generated column is true when the node holds itself" do
    set_state(holds: {"local" => {"since" => "2026-10-07T00:00:00Z", "reason" => "docker-upgrade", "by" => "root"}})
    assert_equal true, raw_maintenance
    assert_equal true, @node.maintenance
    refute_includes Node.online, @node
    refute_includes Node.available, @node
    assert_includes Node.offline, @node
  end

  test "writes to the generated column are silently dropped, and reload reads the derived value" do
    @node.update!(maintenance: true)
    assert_equal false, @node.reload.maintenance

    @node.update!(maintenance_requested: true)
    # The in-memory attribute is NOT refreshed by a save.
    assert_equal true, @node.reload.maintenance
  end

  # --- helpers ---------------------------------------------------------------------

  test "maintenance_held_by and hold readers" do
    set_state
    assert_equal [], @node.maintenance_held_by
    assert_nil @node.maintenance_local_hold
    assert_nil @node.maintenance_controller_hold

    set_state(requested: true, holds: {"local" => nil, "controller" => {"gen" => 1}})
    assert_equal ["controller"], @node.maintenance_held_by
    assert_equal({"gen" => 1}, @node.maintenance_controller_hold)

    set_state(holds: {"local" => {"by" => "root"}})
    assert_equal ["node"], @node.maintenance_held_by
    assert_equal({"by" => "root"}, @node.maintenance_local_hold)

    set_state(requested: true, holds: {"local" => {"by" => "root"}})
    assert_equal ["controller", "node"], @node.maintenance_held_by
  end

  test "maintenance_since prefers paused_since, falls back to maintenance_updated only while requested" do
    updated = Time.utc(2026, 10, 1, 12, 0, 0)
    @node.update_columns(maintenance_updated: updated)

    set_state
    assert_nil @node.maintenance_since

    set_state(requested: true)
    assert_equal updated, @node.maintenance_since

    set_state(holds: {"local" => {"by" => "root"}, "paused_since" => "2026-10-07T14:02:00Z"})
    assert_equal Time.utc(2026, 10, 7, 14, 2, 0), @node.maintenance_since

    # The agent sends unix seconds.
    set_state(holds: {"local" => {"by" => "root"}, "paused_since" => 1_791_381_720})
    assert_equal Time.at(1_791_381_720).utc, @node.maintenance_since

    set_state(requested: true, holds: {"paused_since" => "garbage"})
    assert_equal updated, @node.maintenance_since
  end

  test "agent_maintenance_supported?" do
    assert @node.agent_token.present?, "fixture node needs an agent token"
    @node.agent_maintenance_unsupported_at = nil
    assert @node.agent_maintenance_supported?
    @node.agent_maintenance_unsupported_at = 10.minutes.ago
    refute @node.agent_maintenance_supported?
    @node.agent_maintenance_unsupported_at = 2.hours.ago
    assert @node.agent_maintenance_supported?
    @node.agent_token_encrypted = nil
    refute @node.agent_maintenance_supported?
  end

  # --- migration backfill -----------------------------------------------------------

  test "the migration backfills a NULL legacy maintenance as not requested" do
    require Rails.root.join("db/migrate/20261007000001_add_maintenance_holds_to_nodes.rb").to_s
    migration = AddMaintenanceHoldsToNodes.new
    other = Node.where.not(id: @node.id).first

    begin
      ActiveRecord::Migration.suppress_messages do
        # Postgres DDL is transactional, so this all rolls back with the test.
        migration.migrate(:down)
        Node.connection.execute("UPDATE nodes SET maintenance = NULL WHERE id = #{@node.id}")
        Node.connection.execute("UPDATE nodes SET maintenance = true WHERE id = #{other.id}") if other
        migration.migrate(:up)
      end
      Node.reset_column_information

      assert_equal false, Node.connection.select_value("SELECT maintenance_requested FROM nodes WHERE id = #{@node.id}")
      assert_equal false, Node.connection.select_value("SELECT maintenance FROM nodes WHERE id = #{@node.id}")
      if other
        assert_equal true, Node.connection.select_value("SELECT maintenance_requested FROM nodes WHERE id = #{other.id}")
      end
    ensure
      Node.reset_column_information
    end
  end

  test "the down migration keeps a locally held node in maintenance" do
    require Rails.root.join("db/migrate/20261007000001_add_maintenance_holds_to_nodes.rb").to_s
    migration = AddMaintenanceHoldsToNodes.new
    set_state(holds: {"local" => {"by" => "root"}})

    begin
      ActiveRecord::Migration.suppress_messages { migration.migrate(:down) }
      assert_equal true, Node.connection.select_value("SELECT maintenance FROM nodes WHERE id = #{@node.id}")
      ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }
    ensure
      Node.reset_column_information
    end
  end
end
