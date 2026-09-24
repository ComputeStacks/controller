module Events
  module CodeState
    extend ActiveSupport::Concern

    included do
      scope :starting, -> { where event_code: start_codes }
      scope :stopping, -> { where event_code: stop_codes }
      scope :problems, -> { where event_code: error_codes }
    end

    class_methods do
      ##
      # Track all codes used where start is the final result
      #
      # * f59498e7717c7106 -- start
      # * d611b2bbf50bd48c -- restart
      # * 14bbe1dc184afba0 -- rebuild
      # * 0a3af01a3384fa10 -- New Order Provisioner
      def start_codes
        %w[
          f59498e7717c7106
          d611b2bbf50bd48c
          14bbe1dc184afba0
          0a3af01a3384fa10
        ]
      end

      ##
      # Track all codes used where stop is the final result
      #
      # * 0b264bd661e2d449 -- stop
      def stop_codes
        %w[
          0b264bd661e2d449
        ]
      end

      ##
      # Track codes that identify a problem with the resource
      #
      # * 459363d1cbcce0c3 -- Container is not staying online
      def error_codes
        %w[
          459363d1cbcce0c3
        ]
      end

      ##
      # Track codes for read-only / background operations that must NOT count as a
      # blocking operation (see Volume#operation_in_progress?). A backup export runs
      # read-only with `borg export-tar --bypass-lock`, so it coexists with
      # backups/restores/deletes.
      #
      # * agent-e7c1a9d4b6f20835 -- backup export / download
      def non_blocking_codes
        [EventLog::BACKUP_EXPORT_EVENT_CODE]
      end
    end
  end
end
