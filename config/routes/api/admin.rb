Rails.application.routes.draw do

  namespace :api do
    namespace :admin do

      resources :billing_plans do
        scope module: 'billing_plans' do
          resources :billing_resources do
            scope module: 'billing_resources' do
              resources :billing_phases do
                scope module: 'billing_phases' do
                  resources :billing_resource_prices
                end
              end
            end
          end
        end
      end

      resources :container_images do
        scope module: 'container_images' do
          resources :image_variants do
            scope module: 'image_variants' do
              resources :pull
            end
          end
          resources :collaborators, :pull
        end
      end

      resources :container_registry do
        scope module: 'container_registry' do
          resources :collaborators
        end
      end

      namespace :networks do
        resources :ingress_rules
      end

      resources :users do
        scope module: 'users' do
          delete 'suspension', to: 'suspension#destroy'
          resources :api_credentials, :prices, :ssh_keys, :suspension, :user_sso
        end
        # get 'orders(/filter/:filter)', to: 'orders#index'
        # get 'orders', to: 'orders#index'
        get 'projects', to: 'projects#index'
        get 'billing_events', to: 'subscriptions/billing_events#index'
        get 'billing_usages', to: 'subscriptions/billing_usages#index'
        get 'subscriptions', to: 'subscriptions#index'
        get 'subscriptions/filter/:filter', to: 'subscriptions#index'
        # get 'orders/filter/:filter', to: 'orders#index'
        # resources :zones, :orders
      end

      # Should be patch, but support 'put'.
      match 'subscriptions/:id/suspend', to: 'subscriptions#suspend', via: %i[ put patch ]
      match 'subscriptions/:id/unsuspend', to: 'subscriptions#unsuspend', via: %i[ put patch ]

      get 'subscriptions/filter/:filter', to: 'subscriptions#index'
      resources :subscriptions do
        scope module: 'subscriptions' do
          post 'suspension', to: 'suspension#create'
          delete 'suspension', to: 'suspension#destroy'
          resources :billing_events, :billing_usages
        end
      end

      # get 'orders/filter/:filter', to: 'orders#index'
      # put 'orders/:id/process', to: 'orders#process_order'

      resources :locations do
        scope module: 'locations' do
          resources :allocated_resources
          resources :regions do
            scope module: 'regions' do
              resources :nodes do
                scope module: 'nodes' do
                  resources :maintenance
                end
              end
            end
          end
        end
      end

      get 'orders/filter/:filter', to: 'orders#index'
      resources :orders do
        scope module: 'orders' do
          resources :process_order, only: :create
        end
      end

      resources :projects do
        scope module: 'projects' do
          resources :collaborators
        end
      end

      resources :zones do
        scope module: 'zones' do
          resources :collaborators
        end
      end

      resources :container_services,
                :domains,
                :event_logs,
                :image_collections,
                :products,
                :user_groups,
                :volumes
    end
  end

end
