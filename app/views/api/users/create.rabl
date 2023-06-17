object false

node :user do
  {
    id: @user.id,
    fname: @user.fname,
    lname: @user.lname,
    email: @user.email,
    currency: @user.currency,
    api: {
      username: @api_credential&.username,
      password: @api_credential&.generated_password
    },
    labels: @user.labels
  }
end
