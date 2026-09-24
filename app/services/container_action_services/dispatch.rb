module ContainerActionServices
  ##
  # Executes a single container_action_request: atomically claim it, resolve the
  # engine-registered handler, enforce engine-ownership, run it, and record the
  # outcome on the row's state machine.
  #
  # Core is generic — it defines no actions and holds no project→engine map. The
  # handler (a commercial engine) owns all action semantics AND the ownership authz
  # (`owns?`), so a container can request any action_type string but only an action
  # whose engine claims the project ever executes.
  class Dispatch
    # @param req [ContainerActionRequest]
    def initialize(req)
      @req = req
    end

    def call
      # Atomic claim: only the worker that flips received/failed -> dispatching
      # proceeds, so the handler runs at most once even with duplicate workers.
      return unless @req.dispatch!

      handler_class = ContainerActionRegistry.handler_for(@req.action_type)
      return @req.unhandled!("no handler for #{@req.action_type}") if handler_class.nil?

      # project_id is agent-attested (per-node admin Bearer), resolved against the
      # global id space. NOTE: we intentionally do NOT verify the deployment is hosted
      # on the reporting node (@req.node) — node_id is provenance only. A compromised
      # agent could target another node's project; a node<->project binding check is a
      # deferred defense-in-depth (it would false-negative for projects with no running
      # containers, which resolve to no node).
      deployment = Deployment.find_by(id: @req.project_id.to_i)
      return @req.reject!("unknown project #{@req.project_id}") if deployment.nil?
      @req.update(deployment: deployment)

      handler = handler_class.new
      return @req.reject!("engine does not own project #{deployment.id}") unless handler.owns?(deployment)

      apply handler.call(@req)
    rescue => e
      ExceptionAlertService.new(e, "649da18ea1123477").perform
      @req.retry_later!("dispatch error: #{e.class}: #{e.message}")
    end

    private

    # @param result [#status, #reason, #http_status]
    def apply(result)
      case result.status
      when :accepted
        @req.complete!(result_hash(result))
      when :rejected # permanent failure — handler rejected the request (e.g. a bad 4xx)
        @req.kill!("handler rejected: #{result.reason}")
        record_dead
      else # :failed — transient (429 / 5xx / timeout)
        @req.retry_later!("transient: #{result.reason}")
      end
    end

    def result_hash(result)
      {"status" => result.status.to_s, "reason" => result.reason, "http_status" => result.http_status}
    end

    # A permanently-failed action must be visible, not silently dropped.
    def record_dead
      SystemEvent.create!(
        message: "Container action #{@req.action_type} permanently failed for project #{@req.project_id}",
        log_level: "warn",
        data: {"action_id" => @req.action_id, "state_reason" => @req.state_reason},
        event_code: "544f4c5484f7d0b7"
      )
      Audit.create_from_object!(@req.deployment, "container_action", "127.0.0.1") if @req.deployment
    end
  end
end
