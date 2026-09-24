module ContainerActionServices
  ##
  # The reaction pass over projected `container_action_requests`. Idempotent and safe
  # to run every tick, independent of changelog activity (so failed rows retry and
  # stuck rows reap even when the agent is quiet).
  class Sweep
    # Max dispatches enqueued per project per sweep — controller-side rate limit /
    # defense in depth (the agent debounces upstream, the target throttles
    # downstream). Over-budget rows stay actionable for the next sweep.
    PER_PROJECT_BUDGET = 5

    def call
      reap_stuck
      coalesce_duplicates
      enqueue_actionable
    end

    private

    # Return rows abandoned mid-dispatch (worker died) to the retry path.
    def reap_stuck
      ContainerActionRequest.where(status: "dispatching").find_each do |req|
        req.retry_later!("dispatch worker did not complete (stuck)") if req.stuck?
      end
    end

    # Collapse exact-duplicate pending actions: same project, same action_type, and
    # identical params are redundant (re-running one is pointless), so keep the newest
    # and supersede the rest. Generic and action-agnostic — core never inspects what
    # params mean; requests that differ in any way are left to dispatch on their own.
    def coalesce_duplicates
      ContainerActionRequest.actionable.to_a
        .group_by { |r| [r.project_id, r.action_type, r.params] }
        .each_value do |group|
          next if group.size < 2
          winner = group.max_by(&:changelog_seq)
          (group - [winner]).each { |r| r.supersede!(by: winner.action_id) }
        end
    end

    def enqueue_actionable
      ContainerActionRequest.actionable.order(:changelog_seq)
        .group_by(&:project_id).each_value do |group|
          group.first(PER_PROJECT_BUDGET).each do |req|
            ContainerActionWorkers::DispatchWorker.perform_async req.id
          end
        end
    end
  end
end
