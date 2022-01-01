object false

node :events do
  @events.map do |i|
    partial "api/event_logs/event_log", object: i
  end
end