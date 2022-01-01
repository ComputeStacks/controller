collection @users
attributes :id, :fname, :lname, :email, :active, :is_admin, :api_key, :api_version, :external_id, :billing_plan_id, :currency, :confirmed_at, :confirmation_sent_at, :last_request_at, :last_sign_in_at, :current_sign_in_at, :sign_in_count, :reset_password_sent_at, :locked_at, :failed_attempts, :address1, :address2, :city, :state, :zip, :country, :vat, :created_at, :updated_at
node :current_sign_in_ip do |user|
  user.current_sign_in_ip.to_s
end
node :last_sign_in_ip do |user|
  user.last_sign_in_ip.to_s
end
child({security_keys: :security_keys}, object_root: false) do
  attributes :id, :label, :is_type, :public_key, :created_at, :updated_at
end
child({billing_plan: :billing_plan}, object_root: false) do
  attributes :id, :name
end
