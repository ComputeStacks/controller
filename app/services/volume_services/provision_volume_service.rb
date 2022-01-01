module VolumeServices
  ##
  # Provision Volume
  #
  # @!attribute volume
  #   @return [Volume]
  # @!attribute event
  #   @return [EventLog]
  class ProvisionVolumeService

    attr_accessor :volume,
                  :event

    # @param [Volume] volume
    # @param [EventLog] event
    def initialize(volume, event)
      self.volume = volume
      self.event = event
    end

    # @return [Boolean]
    def perform
      client = volume.volume_client
      if client.create!
        volume.update_consul!
        true
      else
        if event
          event.event_details.create!(
            data: client.errors.empty? ? "Fatal error" : client.errors.join(' '),
            event_code: '3ace7a0db8fcc88f'
          )
        end
        false
      end
    rescue Excon::Error::Socket, Errno::ECONNREFUSED, IO::EINPROGRESSWaitWritable => connection_error
      SystemEvent.create!(
        message: "Error creating volume.",
        log_level: "warn",
        data: {
          volume: volume.inspect,
          error: connection_error.message
        },
        event_code: '04bed58fa43fab49'
      )
      event.event_details.create!(data: connection_error.message, event_code: "04bed58fa43fab49") if event
      false
    rescue Docker::Error::ServerError => server_error
      ExceptionAlertService.new(e, '7644f82e2a97cd0e').perform
      SystemEvent.create!(
        message: "Error creating volume.",
        log_level: "warn",
        data: {
          volume: volume.inspect,
          error: server_error.message
        },
        event_code: '7644f82e2a97cd0e'
      )
      event.event_details.create!(data: server_error.message, event_code: "7644f82e2a97cd0e") if event
      false
    rescue => e
      ExceptionAlertService.new(e, 'cec8b7094470e525').perform
      SystemEvent.create!(
        message: "Error creating volume.",
        log_level: "warn",
        data: {
          volume: volume&.inspect,
          error: e.message
        },
        event_code: 'cec8b7094470e525'
      )
      event.event_details.create!(data: e.message, event_code: "cec8b7094470e525") if event
      false
    end

  end
end
