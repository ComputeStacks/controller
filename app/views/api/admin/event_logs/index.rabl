collection @events
attributes :id, :description, :status, :state_reason, :event_code, :created_at, :updated_at
attributes :locale => :event, :locale_keys => :event_attributes
child({audit: :audit_log}, object_root: false) do
  attributes :id, :event, :ip_addr, :created_at, :updated_at
  child :user do
    attribute :id, :fname, :lname, :email
  end
end