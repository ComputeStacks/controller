attributes :id, :locale, :status, :notice, :state_reason, :event_code, :description, :created_at, :updated_at
child :audit do
  attributes :id, :event, :raw_data, :created_at, :updated_at
  node :user do |i|
    {
      id: i.user&.id,
      name: i.user&.full_name
    }
  end
  node :ip_addr do |i|
    i.ip_addr.to_s
  end
end
