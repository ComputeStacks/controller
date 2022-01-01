#require 'github/markup'
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
    end

    @events = EventLog.failed.recent.count
    @alerts = AlertNotification.active.admin_only.count

    if request.xhr?
      render template: 'admin/dashboard/health', layout: false
    end

    # @system_ok = @bypassed_users.empty? && @offline_drivers.empty? && @offline_nodes.empty?
    # @system_warning = !@maintenance_nodes.empty? || !@warning_nodes.empty? || !@events.zero? || !@alerts.zero?
  end

  def changelog
    @changelog = File.read("CHANGELOG.html")
    # @encoder_info = RGLoader::get_const("encoder")
  rescue => e
    ExceptionAlertService.new(e, 'c09f4ff037723b6b').perform
    @changelog = "Error!: #{e.message}"
  end

end
