object @user
attributes :id, :email
node :auth_token do
  @token
end
node :auth_expiration do
  @expires
end