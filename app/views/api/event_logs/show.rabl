object false

node :event_log do
  partial "api/event_logs/event_log_detail", object: @event
end

