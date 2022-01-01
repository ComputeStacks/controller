Rails.application.routes.draw do

  namespace :api do
    namespace :stacks do
      get 'assets/:id', to: 'stack_assets#show'
      post 'load_balancers/provision', to: 'load_balancers#provision'
      get 'load_balancers/assets/:file', to: 'load_balancers#assets'
      resources :load_balancers
    end
  end

end