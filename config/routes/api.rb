Rails.application.routes.draw do

  ## LetsEncrypt
  get '.well-known/acme-challenge/:id', to: 'acme_validator#show'

  load Rails.root.join('config/routes/api/admin.rb')
  load Rails.root.join('config/routes/api/stacks.rb')
  load Rails.root.join('config/routes/api/system.rb')
  load Rails.root.join('config/routes/api/user.rb')

  scope 'api' do
    use_doorkeeper do
      controllers authorizations: 'auth/oauth_authorizations',
                  applications: 'auth/oauth_applications',
                  authorized_applications: 'auth/oauth_authorized_applications',
                  tokens: 'auth/oauth_tokens'
    end
  end

  namespace :api do

    post 'auth', to: 'application#auth'
    post 'user/:external_id/authcheck', to: 'application#secondfactor'
    get 'version', to: 'application#version'

    namespace :cluster do
      resources :assets
    end


    match '/', to: 'application#unknown_route', via: :all
    match '*path', to: 'application#unknown_route', via: :all
  end
end
