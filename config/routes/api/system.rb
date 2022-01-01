Rails.application.routes.draw do

  namespace :api do
    namespace :system do
      # resources :ingress_rules, only: [ :index ]
      resources :alert_notifications, :events
    end
  end

end
