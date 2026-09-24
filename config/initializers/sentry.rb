##
# Sentry
#
SENTRY_CONFIGURED = !ENV["SENTRY_DSN"].blank?
if SENTRY_CONFIGURED
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]
    config.enabled_environments = %w[default test development production] # Default is used by clockwork
    config.release = "controller@#{File.read("#{Rails.root}/VERSION").strip}"

    # Send request-scoped PII (client address, headers, cookies). Rails'
    # filter_parameters still applies to request params, and Sentry's own data
    # scrubbers run on ingest.
    config.send_default_pii = true

    # Structured logging (the Sentry Logs product) is OFF.
    #
    # sentry 7.0.0 turned it on by default -- 6.x gated it behind `enable_logs`,
    # which defaulted to false. Enabled, it attaches a log subscriber per component
    # and emits one Sentry log event for every SQL query the app runs. Those events
    # buffer and, every LogEventBuffer::DEFAULT_MAX_EVENTS (100), flush over HTTPS
    # SYNCHRONOUSLY on whichever thread happened to run the hundredth query.
    #
    # This Sentry is in San Jose and this controller is in Amsterdam, so a flush is a
    # ~435ms round trip (292ms of it a fresh TLS handshake -- the connection is not
    # reused). That is a hidden ~4.3ms tax on every query in the application, and it
    # turns any N+1 into an outage: an order's zone-capacity scan issues ~11,800
    # queries, which is ~117 flushes, which is ~51s -- past the proxy's timeout.
    #
    # We do not use Sentry Logs; this restores 9.7.5 behaviour. Exception capture,
    # breadcrumbs and tracing are unaffected -- they are separate products and none
    # of them fire per query.
    config.rails.structured_logging.enabled = false

    config.traces_sample_rate = if ENV["SENTRY_TRACE_SAMPLE_RATE"].blank?
      0.2
    else
      ENV["SENTRY_TRACE_SAMPLE_RATE"].to_f.clamp(0.0, 1.0)
    end

    ##
    # Attribute an event to the installation that sent it.
    #
    # Without this, an event raised outside a web request (any worker or clock
    # job) carries no network identity: the SDK attaches no address, and Sentry
    # only derives a country from the connecting IP before discarding it. The
    # "{{auto}}" sentinel tells Sentry to record the address our process
    # connected from. An IP set elsewhere — a real end user, behind the
    # collect_user_info / exception_user_info features — is left alone.
    config.before_send = lambda do |event, _hint|
      next event unless event.respond_to?(:user)
      user = event.user || {}
      event.user = user.merge(ip_address: "{{auto}}") if user[:ip_address].blank? && user["ip_address"].blank?
      event
    end
  end
end
