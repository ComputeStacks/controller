module NetworkServices
  class GenerateProjectNetworkService

    attr_reader :event,
                :region,
                :project

    attr_accessor :network

    # @param [EventLog] event
    # @param [Region] region
    # @param [Deployment] project
    def initialize(event, region, project)
      @event = event
      @region = region
      @project = project
    end

    # @return [Boolean]
    def perform
      if @region.has_clustered_networking?
        @event.event_details.create!(
          data: "Region is configured for clustered networking, skipping.",
          event_code: "6815ed448c0f5073"
        )
        return true
      end
      unless @project.private_network.nil?
        @event.event_details.create!(
          data: "Project network already configured, skipping.",
          event_code: "159f58a91922552b"
        )
        return true
      end
      # find shared network
      nets = @region.networks.bridged.shared
      if nets.empty?
        @event.event_details.create!(
          data: "Failed to generate private project network. Missing region network definition.",
          event_code: "89d0b4ca6d29d9ef"
        )
        return false
      end

      self.network = nil
      nets.each do |i|
        i.child_networks.bridged.inactive.each do |child|
          next unless child.deployment.nil?
          self.network = child
          break
        end
      end

      if network.nil?
        @event.event_details.create!(
          data: "Failed to find a free network to allocate.",
          event_code: "84a4f325917d03ee"
        )
        return false
      end

      unless network.update(deployment: project, name: "net-#{@project.token}", label: "net-#{@project.token}")
        @event.event_details.create!(
          data: "Failed to allocate network #{n.name}\n\n#{n.errors.full_messages.join(',')}",
          event_code: "5c01346cba94202e"
        )
        return false
      end
      # Provision on node
      NetworkServices::CreateBridgeNetworkService.new(network, event).perform
      true
    end

  end
end
