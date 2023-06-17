object @user
attributes :id, :fname, :lname, :email, :active, :company_name, :is_admin, :api_key, :api_version, :external_id, :billing_plan_id, :currency, :confirmed_at, :confirmation_sent_at, :last_request_at, :last_sign_in_at, :current_sign_in_at, :sign_in_count, :reset_password_sent_at, :locked_at, :failed_attempts, :address1, :address2, :city, :state, :zip, :country, :vat, :user_group_id, :created_at, :updated_at, :auth_token, :auth_token_exp, :labels
node :currency_symbol do |i|
  Money.new(1, i.currency).symbol
end
node :current_sign_in_ip do |user|
  user.current_sign_in_ip.to_s
end
node :last_sign_in_ip do |user|
  user.last_sign_in_ip.to_s
end
