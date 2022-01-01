object @user
attributes :id, :email, :auth_token, :external_id, :currency
attribute auth_token_exp: :auth_expiration
node :currency_symbol do |i|
  Money.new(1, i.currency).symbol
end