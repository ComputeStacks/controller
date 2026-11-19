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
      # Cheap, unlocked early-out; `claim_network!` re-checks under the lock.
      if Network.exists?(deployment_id: @project.id)
        skip_existing!
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
      outcome = claim_network!(nets)

      case outcome
      when :exists
        # Another caller bound one between the early-out above and the lock.
        skip_existing!
        return true
      when :none
        @event.event_details.create!(
          data: "Failed to find a free network to allocate.",
          event_code: "84a4f325917d03ee"
        )
        return false
      when :invalid
        @event.event_details.create!(
          data: "Failed to allocate network #{network.name}\n\n#{network.errors.full_messages.join(",")}",
          event_code: "5c01346cba94202e"
        )
        return false
      end
      # Provision on node.
      #
      # Return the result. This used to discard it and answer `true` unconditionally, so a
      # network that failed to reach the node still reported success: ProcessOrderService
      # carried on, built every container, and each one failed to start with "network ...
      # not found". The customer saw a fatal error per container instead of one clear
      # "Failed to build project network", and the order left containers behind.
      #
      # Outside the lock on purpose: this is node I/O.
      NetworkServices::CreateBridgeNetworkService.new(network, event).perform
    end

    private

    def skip_existing!
      @event.event_details.create!(
        data: "Project network already configured, skipping.",
        event_code: "159f58a91922552b"
      )
    end

    ##
    # Bind a free child network to the project, atomically.
    #
    # This used to be a plain read ("first inactive child with no deployment") followed by an
    # unlocked `update`. On 2026-10-20 five orders ran within 1.5s, two of them read the same
    # free row, and the one that wrote last owned it -- the other's service still answered
    # true, and its containers were created with no network at all.
    #
    # Two locks, for two different races:
    # * the project row, so two callers for the SAME project (an order and a build-path
    #   repair, see EnsureContainerNetworkService) cannot both allocate one. Taken on a fresh
    #   query rather than `@project.with_lock`, which would reload the caller's object and
    #   raise if it had unsaved changes.
    # * the candidate row, with SKIP LOCKED, so callers for DIFFERENT projects each get their
    #   own row without queueing behind each other.
    #
    # The existence check is a query, not `@project.private_network`: that `has_one` is
    # cached, and is nil for the whole life of an order that has not reloaded the project
    # (see ProcessOrderService#release_network!).
    #
    # No `return` inside the transaction block (non-local return semantics under the 7.0
    # defaults); the result is computed inside and acted on by the caller.
    #
    # @return [Symbol] :exists, :none, :invalid or :claimed (with `network` set)
    def claim_network!(nets)
      Deployment.transaction do
        Deployment.where(id: @project.id).lock.pluck(:id)
        if Network.exists?(deployment_id: @project.id)
          :exists
        else
          candidate = Network.where(parent_network_id: nets.select(:id))
            .bridged
            .inactive
            .where(deployment_id: nil)
            .order(:id)
            .lock("FOR UPDATE SKIP LOCKED")
            .first
          if candidate.nil?
            :none
          else
            self.network = candidate
            # `update`, not `update_all`: `format_network_name` and the uniqueness validations
            # still need to run.
            if candidate.update(deployment: @project, name: "net-#{@project.token}", label: "net-#{@project.token}")
              :claimed
            else
              :invalid
            end
          end
        end
      end
    end
  end
end
