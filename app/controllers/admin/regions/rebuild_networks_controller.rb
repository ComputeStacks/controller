class Admin::Regions::RebuildNetworksController < Admin::ApplicationController
  def create
    @region = Region.find_by id: params[:region_id]

    if @region.nil?
      redirect_to "/admin/regions", alert: "Region not found."
      return false
    end

    audit = Audit.create_from_object!(@region, "updated", request.remote_ip, current_user)
    event = audit.event_logs.create!(
      locale_keys: {
        region: @region.name
      },
      locale: "region.rebuild_networks",
      event_code: "02b8263f67ae56f0",
      status: "pending"
    )

    RegionWorkers::RebuildNetworksWorker.perform_async @region.id, event.id

    redirect_to "/admin/event_logs/#{event.id}", notice: "Rebuild network will begin shortly."
  end
end
