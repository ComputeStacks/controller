module ImageWorkers
  ##
  # Plan the cascade of a newly added image volume template onto every already-deployed
  # container service of that image.
  #
  # This worker does no provisioning of its own: it fans out one
  # ImageWorkers::AttachVolumeToServiceWorker per service and leaves the parent event
  # `running`. The last child to finish closes it (see that worker's finalisation block).
  # Fanning out removes the single-long-job fragility of the previous implementation across
  # hundreds of services, and keeps one failed service from starving the rest.
  #
  # Queue: `dep_low`. This provisions real volumes on remote nodes, i.e. deployment-domain
  # work served by `worker_deployments` (config/sidekiq/deployments.yml.erb). The previous
  # implementation sat on `default` (`worker_system`).
  #
  # `retry: false`: the planner is idempotent only in the sense that its children are, and a
  # retry after a partial fan-out would double-count `expected`. Recovery is by re-running the
  # (idempotent) retroactive cascade action, which is exactly why that entry point exists.
  class CascadeVolumeChangeWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: "dep_low"

    REF_PARAM_EVENT_CODE = "59b4a857bcbaef69".freeze
    NO_SERVICES_EVENT_CODE = "fc3f3bf31bafaa42".freeze
    DISPATCHED_EVENT_CODE = "0f3ad98508fe9f5d".freeze

    # @param [Integer] volume_param_id
    # @param [Integer] event_id
    def perform(volume_param_id, event_id)
      volume_param = ContainerImage::VolumeParam.find_by id: volume_param_id
      return nil if volume_param.nil?

      event = EventLog.find_by id: event_id
      return nil if event.nil?

      event.start!

      if volume_param.source_volume.present?
        event.event_details.create!(
          data: "This volume references another image's volume; there is nothing to create.",
          event_code: REF_PARAM_EVENT_CODE
        )
        event.done! "Nothing to do"
        return nil
      end

      services = volume_param.container_image.deployed_services.to_a

      if services.empty?
        event.event_details.create!(
          data: "No deployed services use this image; nothing to do.",
          event_code: NO_SERVICES_EVENT_CODE
        )
        event.done! "No deployed services"
        return nil
      end

      # Write the counters BEFORE enqueuing anything: a child that observes `expected` = 0
      # would immediately think the fan-out was complete and close the parent event.
      event.update! labels: event.labels.merge(
        "expected" => services.count,
        "completed" => 0,
        "created" => 0,
        "skipped" => 0,
        "failed" => 0
      )

      services.each do |service|
        ImageWorkers::AttachVolumeToServiceWorker.perform_async volume_param.id, service.id, event.id
      end

      event.event_details.create!(
        data: "Dispatched #{services.count} #{"service".pluralize(services.count)} for volume attachment.",
        event_code: DISPATCHED_EVENT_CODE
      )

      nil
    end
  end
end
