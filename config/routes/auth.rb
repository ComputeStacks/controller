Rails.application.routes.draw do
  devise_for  :users,
              path_names: { sign_in: 'login', sign_out: 'logout' },
              controllers: { registrations: "registrations", sessions: 'sessions' }

  patch 'users/edit' => 'users#update'
  post 'users/api' => 'users_api#create'
  delete 'users/api' => 'users_api#destroy'

  get 'register' => 'registration#new'
  post 'register' => 'registration#create'

  get 'goodbye', :to => "users#disconnect"
  devise_scope :user do
    get 'login', :to => "sessions#new"
    get "logout", :to => "devise/sessions#destroy"
  end
  #post '/users/validate/sms' => 'users#authy_sms'
  #post '/users/disable-two-factor' => 'users#authy_disable'

  namespace :users do
    get 'authy/verify' => 'authy#edit'
    put 'authy/verify' => 'authy#update'
    delete 'authy' => 'authy#destroy'
    delete 'totp' => 'totp#destroy'
    post 'connection_helper/:id' => 'connection_helper#create'
    resources :security, :security_key, :security_key_auth, :totp, :authy, :api_credentials, :ssh_keys
  end

  resources :collaborations

end
