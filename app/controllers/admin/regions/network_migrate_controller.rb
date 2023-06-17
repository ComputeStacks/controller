class Admin::Regions::NetworkMigrateController < Admin::ApplicationController
  before_action :load_region

  def create
    audit = Audit.create_from_object!(@region, 'updated', request.remote_ip, current_user)
    p = RegionServices::MigrateProjectNetworksService.new @region, audit
    if p.perform
      if p.event
        redirect_to "/admin/event_logs/#{p.event.id}"
      else
        redirect_to "/admin/regions/#{@region.id}", alert: "Missing Event"
      end
    else
      redirect_to "/admin/regions/#{@region.id}", alert: "Error #{p.errors.join(",")}"
    end
  end

  def show
    @event = EventLog.find params[:id]
  end

  private

  def load_region
    @region = Region.find_by(id: params[:region_id])
    if @region.nil?
      redirect_to "/admin/locations", alert: "Unknown Availability Zone."
      return false
    end
  end

end
