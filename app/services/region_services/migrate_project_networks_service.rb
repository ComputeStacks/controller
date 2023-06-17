module RegionServices
  class MigrateProjectNetworksService

    attr_reader :region,
                :audit

    attr_accessor :errors,
                  :event

    # @param [Region] region
    # @param [Audit] audit
    def initialize(region, audit)
      @region = region
      @audit = audit
      self.event = nil
      self.errors = []
    end

    def perform
      return false unless valid?

      # create event
      self.event = EventLog.create!(
        locale: 'region.network',
        locale_keys: { 'region' => @region.name },
        event_code: '1aa76ff818fded56',
        status: 'pending',
        audit: audit
      )

      # Start
      RegionWorkers::MigrateNetworkWorker.perform_async @region.id, event.id

    end

    private

    def valid?
      if region.has_clustered_networking?
        errors << "Region is not configured for private networking"
      end
      if region.networks.bridged.empty?
        errors << "Missing bridged networks"
      end
      if region.deployments.where(private_network: { id: nil }).includes(:private_network).empty?
        errors << "No projects to migrate"
      end
      errors.empty?
    end

  end
end
