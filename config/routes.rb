require 'sidekiq/web'
Rails.application.routes.draw do

  get 'documentation/api', to: 'documentation#api'

  get '500', to: 'exceptions#internal_server_error'

  load Rails.root.join('config/routes/admin.rb')
  load Rails.root.join('config/routes/api.rb')
  load Rails.root.join('config/routes/auth.rb')
  load Rails.root.join('config/routes/deployments.rb')
  load Rails.root.join('config/routes/dns.rb')

  get 'alert_notifications/status' => 'alert_notifications#status'

  get 'search' => 'search#new'
  post 'search' => 'search#create'

  namespace :billing do
    get 'dashboard', to: 'dashboard#index'
  end

  resources :alert_notifications,
            :event_logs,
            :orders,
            :user_notifications

  root to: 'dashboard#default_route'
  get '*path', to: 'application#unknown_route', via: :all
  post '*path', to: 'application#unknown_route', via: :all

end
