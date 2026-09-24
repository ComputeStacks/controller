# require 'github/markup'
class Admin::DashboardController < Admin::ApplicationController
  def index
    # @bypassed_users = User.where(bypass_second_factor: true).where.not(email: 'hello@computestacks.com')
    # @offline_drivers = ProvisionDriver.where(is_online: false)
    # @offline_nodes = Node.where("regions.active = true and nodes.maintenance = false and nodes.disconnected = true and nodes.active = true").joins(:region)
    # @maintenance_nodes = Node.where("regions.active = true and nodes.maintenance = true and nodes.active = true").joins(:region)
    # @warning_nodes = Node.where("regions.active = true and nodes.maintenance = false and nodes.disconnected = false and nodes.failed_health_checks > 0 and nodes.active = true").joins(:region)
    # @system_ok = @bypassed_users.empty? && @offline_drivers.empty? && @offline_nodes.empty?
    # @system_warning = !@maintenance_nodes.empty? || !@warning_nodes.empty?

    unless request.xhr?
      @new_users = User.all.limit(10).order(created_at: :desc)
      # Both halves of the regions panel, for the HTML path only (it is the only
      # path that renders the partial). Three queries whatever the topology,
      # where the view previously issued one per location for its regions and
      # another per region for its load balancer.
      #
      # Ordering is explicit at both levels via the existing `sorted` scopes --
      # neither the old `Location.active` nor `regions.joins(:nodes).distinct`
      # had an ORDER BY, so the panel's row order was whatever Postgres chose.
      #
      # `where(id: Node.select(:region_id))` rather than `has_nodes` (a join)
      # because Postgres rejects `SELECT DISTINCT ... ORDER BY lower(name)` --
      # the ordering expression is not in the select list. The IN subquery needs
      # no DISTINCT and selects exactly the same regions the join did.
      @locations = Location.active.sorted
      @regions_by_location = Region.sorted
        .where(location_id: @locations.map(&:id))
        .where(id: Node.select(:region_id))
        .preload(:load_balancer)
        .group_by(&:location_id)
    end

    @events = EventLog.failed.recent.count
    @alerts = AlertNotification.active.admin_only.count
    @invalid_plans = BillingPlan.invalid_plans

    if request.xhr?
      render template: "admin/dashboard/health", layout: false
    end

    # @system_ok = @bypassed_users.empty? && @offline_drivers.empty? && @offline_nodes.empty?
    # @system_warning = !@maintenance_nodes.empty? || !@warning_nodes.empty? || !@events.zero? || !@alerts.zero?
  end

  def changelog
    @changelog = File.read("CHANGELOG.html")
    # @encoder_info = RGLoader::get_const("encoder")
  rescue => e
    ExceptionAlertService.new(e, "c09f4ff037723b6b").perform
    @changelog = "Error!: #{e.message}"
  end
end
