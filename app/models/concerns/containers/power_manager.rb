module Containers
  module PowerManager
    extend ActiveSupport::Concern

    def start!(event)
      return false if halt_if_duplicated_power_event?(event)
      update req_state: 'running'
      c = docker_client_with_event(event)
      return false if c.nil?
      if respond_to?(:subscription) && subscription
        subscription.unpause! unless subscription.active
      end
      response = c.start
      power_cycle_response('on', response, event)
    end

    # @param [EventLog] event
    # @param [Boolean] allow_none if true, we will return true if the container does not exist.
    def stop!(event, allow_none = false)
      return false if halt_if_duplicated_power_event?(event)
      update req_state: 'stopped'
      c = docker_client_with_event(event, allow_none)
      return true if c.nil? && allow_none
      return false if c.nil?
      response = c.stop
      power_cycle_response('off', response, event)
    end

    def restart!(event)
      return false if halt_if_duplicated_power_event?(event)
      update req_state: 'running'
      c = docker_client_with_event(event)
      return false if c.nil?
      if respond_to?(:subscription) && subscription
        subscription.unpause! unless subscription.active
      end
      response = c.restart
      power_cycle_response('on', response, event)
    end

    def delete_from_node!(event)
      c = docker_client_with_event(event, true)
      unless c.nil?
        c.delete
      end
      true
    end

    private

    # @param [EventLog] event
    # @param [Boolean] ignore_missing If true, we wont create an error if the container is missing
    # @return [Docker::Container]
    def docker_client_with_event(event, ignore_missing = false)
      the_client = docker_client
      if the_client.nil? && !ignore_missing
        update status: 'error'
        event.event_details.create!(
          data: 'Container does not exist on node',
          event_code: '41237d8136741d74'
        )
        event.fail! 'Container does not exist on node'
        return nil
      end
      the_client
    end

    ##
    # Parse and handle final power management action
    #
    # Returns nil when still in progress
    # Otherwise, true/false
    def power_cycle_response(requested_state, rsp, event)
      if rsp.info['State']['Error'].blank?
        update_attribute :status, (requested_state == 'off' ? 'stopped' : 'running')
        event.done! if event.running? && !event.supervised
      else
        update_attribute :status, 'stopped'
        if requested_state == 'on' && (rsp.info['State']['Error'] =~ /Address already assigned in block/ || rsp.info['State']['Error'] =~ /already exists in network/)
          if event.event_details.where(event_code: 'cc40061553c02457').count > 2
            event.event_details.create!(
              data: 'Failed to recovery from address already in use',
              event_code: 'cc40061553c02457'
            )
            event.fail! 'Failed to assign IP Address'
            return false
          else
            event.event_details.create!(
              data: "Attempting to recover from:\n#{rsp.info['State']['Error']}",
              event_code: 'cc40061553c02457'
            )
            ContainerWorkers::ReleaseIpWorker.perform_async global_id, event.global_id
            return nil
          end
        elsif rsp.info['State']['Error'] && rsp.info['State']['Error'].to_s.length < 50
          event.event_details.create!(
            data: rsp.info['State']['Error'],
            event_code: '53d38d3bfc9df98f'
          )
          event.fail! 'Power Cycle Error'
        else
          event.event_details.create!(
            data: rsp.info['State']['Error'],
            event_code: '53d38d3bfc9df98f'
          )
          event.fail! 'Docker client error'
        end
      end
      ((requested_state == 'on' || requested_state == 'restart') && status == 'running') || (requested_state == 'off' && status == 'stopped')
    end

    ##
    # Determine if we're actively performing a power action, and if so, halt it.

    # @param [EventLog] event
    # @return [Boolean]
    def halt_if_duplicated_power_event?(event)
      return false unless power_cycle_in_progress?(event)
      event.event_details.create!(
        data: "Action already in progress, please try again later.",
        event_code: 'ff2cd25a592f2cd1'
      )
      event.cancel! 'Action already in progress'
      true
    end

    # @param [EventLog] event
    # @return [Boolean]
    def power_cycle_in_progress?(event)
      return true if event_logs.where.not(id: event.id).where(event_code: event.event_code).active.exists?
      return true if event_logs.where.not(id: event.id).starting.active.exists?
      return true if event_logs.where.not(id: event.id).stopping.active.exists?
      false
    end

  end
end
