module RegionWorkers
  class RebuildNetworksWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform(region_id, event_id)
      region = Region.find region_id
      event = EventLog.find event_id

      event.start!

      region.networks.active.each do |network|
        next if network.deployment.nil?
        next if network.is_shared
        next unless network.network_driver == "bridge"

        NetworkServices::RebuildInterfaceService.new(network, event).perform

        # Don't overload the node.
        sleep 2
      end

      event.done!
    rescue ActiveRecord::RecordNotFound
      event.fail! "Unknown object."
      nil
    rescue => e
      ExceptionAlertService.new(e, "bba725c6a44e9de6").perform
      event.event_details.create!(data: e.message, event_code: "bba725c6a44e9de6")
      event.fail! "Fatal Error"
    end
  end
end
