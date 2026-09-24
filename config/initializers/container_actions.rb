##
# Generic container-action dispatch registry.
#
# Core defines ZERO actions. Engines register a handler per `action_type` in their
# Engine's `after_initialize`, exactly like ENGINE_VIEW_OVERRIDES
# (config/initializers/engine_configuration.rb) — a boot constant, so it is NOT under
# the autoload paths and survives Zeitwerk code reloading in development.
#
# Handlers are registered by CLASS-NAME STRING and constantized lazily at dispatch
# time (mirrors how the view-override hash stores a string path, not a class): the
# stored reference can't go stale across reloads, and a deployment where the owning
# (commercial) engine is absent simply resolves to nil and the action is marked
# `unhandled` rather than crashing.
#
# A handler is a plain object responding to:
#   #owns?(deployment) -> Boolean          # engine-ownership authz for this project
#   #call(container_action_request) -> result responding to #status (:accepted |
#                                          :rejected | :failed), #reason, #http_status
module ContainerActionRegistry
  @handlers = {}

  class << self
    # @param action_type [String, Symbol]
    # @param handler_class_name [String, Class]
    def register(action_type, handler_class_name)
      @handlers[action_type.to_s] = handler_class_name.to_s
    end

    # @return [Boolean]
    def handles?(action_type)
      @handlers.key?(action_type.to_s)
    end

    # @return [Class, nil] nil when no handler is registered (owning engine absent).
    def handler_for(action_type)
      @handlers[action_type.to_s]&.constantize
    end

    # @return [Hash{String=>String}]
    def registered
      @handlers.dup
    end
  end
end
