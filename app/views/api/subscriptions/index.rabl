object false

node :subscriptions do
  @subscriptions.map do |i|
    partial "api/subscriptions/subscription", object: i
  end
end