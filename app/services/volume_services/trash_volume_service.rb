module VolumeServices
  ##
  # Manage deleting a single volume
  #
  # @!attribute volume
  #   @return [Volume]
  # @!attribute event
  #   @return [EventLog]
  class TrashVolumeService

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
      return false unless valid?
      client = volume.volume_client
      if client.destroy
        event.done!
        if volume.destroy
          true
        else
          event.event_details.create!(
            data: "Error removing volume: #{volume.errors.full_messages.join(' ')}",
            event_code: '4fa6b02530dba3f2'
          )
          false
        end
      else
        event.event_details.create!(
          data: "Fatal error: #{client.errors.join(' ')}",
          event_code: '12792dca1a42af90'
        )
        event.fail! 'Fatal Error'
        false
      end
    rescue Docker::Error::ConflictError => e
      unless volume
        msg = e.message =~ /volume is in use/ ? "Volume is in use, unable to delete." : e.message
        ec = "ba4fba2593684508-#{volume.id}"
        system_event = SystemEvent.find_by(event_code: ec)
        if system_event
          d = system_event.data
          if d[:count].is_a?(Integer)
            d[:count] += 1
          elsif d[:count].is_a?(String)
            d[:count].to_i += 1
          end
          system_event.update data: d
        else
          SystemEvent.create!(
            message: "Error deleting volume #{volume.id} (#{volume.label})",
            data: {
              error: msg,
              volume: volume.id,
              count: 1
            },
            event_code: ec
          )
        end
      end
      false
    rescue Excon::Error::Socket, Errno::ECONNREFUSED, IO::EINPROGRESSWaitWritable => connection_error
      SystemEvent.create!(
        message: "Error Deleting volume.",
        log_level: "warn",
        data: {
          volume: volume.inspect,
          error: connection_error.message
        },
        event_code: 'e35d26dfff01309d'
      )
      event.event_details.create!(data: connection_error.message, event_code: "e35d26dfff01309d") if event
      false
    rescue => e
      ExceptionAlertService.new(e, '524cded8b41c4ee9').perform
      SystemEvent.create!(
        message: "Error deleting volume.",
        log_level: "warn",
        data: {
          volume: volume&.inspect,
          error: e.message
        },
        event_code: '524cded8b41c4ee9'
      )
      event.event_details.create!(data: e.message, event_code: "524cded8b41c4ee9") if event
      false
    end

    private

    # @return [Boolean]
    def valid?
      unless volume.can_trash?
        event.fail! 'Volume is in invalid state.'
        return false
      end
      if volume.find_node.nil? || !volume.find_node.online?
        event.fail! 'Unable to find online node'
        return false
      end
      true
    end

  end
end
