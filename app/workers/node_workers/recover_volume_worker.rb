module NodeWorkers
  ##
  # After a node comes back online, this is triggered to attempt to
  # create any volumes that were missed while it was offline.
  class RecoverVolumeWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: 'low'

    def perform(node_id)
      node = GlobalID::Locator.locate node_id
      return unless node.is_a? Node
      audit = Audit.create_from_object!(node, 'updated', '127.0.0.1')
      # Any volumes created after the node was disconnected (well, 5 minutes before), re-run their creation script.
      node.volumes.where( Arel.sql( %Q(created_at >= '#{(node.disconnected_at - 5.minutes).iso8601}') ) ).each do |vol|
        event = EventLog.create!(
          locale: 'node.volumes.provision',
          locale_keys: {
            'volume' => vol.name,
            'node' => node.label
          },
          event_code: 'a3a254679d1d2966',
          status: 'running',
          audit: audit
        )
        event.volumes << vol
        event.nodes << node
        VolumeServices::ProvisionVolumeService.new(vol, event).perform

        failed_even_codes = %w(7644f82e2a97cd0e cec8b7094470e525 b4e181611d7c5423)

        if event.event_details.where( Arel.sql( %Q(event_code IN (#{failed_even_codes.join(',')}) ) ) ).exists?
          event.fail! 'Fatal Error'
        else
          event.done!
        end
      end
    rescue => e
      ExceptionAlertService.new(e, 'b51ff7962fa47262').perform
    end

  end
end
