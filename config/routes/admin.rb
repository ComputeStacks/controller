Rails.application.routes.draw do

  get 'admin' => redirect('/admin/dashboard') # Redirect /admin to Dashboard

  namespace :admin do

    ##
    # Custom Routes
    get 'changelog' => 'dashboard#changelog'
    get 'dns/filter/:filter' => 'dns#index'
    put 'orders/:id/process' => 'orders#process_order' # Process a single order
    delete 'system_events/all', to: 'system_events#destroy_all' # Mass delete system events
    get 'system_events/filter/:filter(/:filter_id)', to: 'system_events#index' # Filter system events
    post 'users/:id/become' => 'users#impersonate'
    delete 'volumes', to: 'volumes#destroy'

    resources :container_registry do
      scope module: 'container_registry' do
        resources :collaborators
      end
    end

    resources :billing_plans do
      scope module: 'billing_plans' do
        resources :billing_resources
        resources :billing_phases do
          scope module: 'billing_phases' do
            resources :billing_resource_prices
          end
        end
      end
    end

    resources :blocks do
      scope module: 'blocks' do
        resources :block_contents
      end
    end

    resources :containers do
      scope module: 'containers' do
        resources :events, :migrate_container, :power, :remote_volumes
      end
    end

    namespace :container_images do
      resources :image_validation, :providers
    end

    resources :container_image_collections do
      scope module: 'container_image_collections' do
        resources :container_image
      end
    end

    resources :container_images do
      scope module: 'container_images' do
        resources :collaborators,
                  :env_params,
                  :image_relationships,
                  :image_variants,
                  :ingress_params,
                  :setting_params,
                  :volume_params,
                  :pull
      end
    end

    resources :deployments do
      scope module: 'deployments' do

        resources :domains do
          scope module: 'domains' do
            resources :verify_dns
          end
        end

        resources :services do
          scope module: 'services' do
            resources :containers, :events
          end
        end

        resources :collaborators, :events, :sftp, :volumes

      end
    end

    resources :dns do
      scope module: 'dns' do
        resources :collaborators, :records
      end
    end

    resources :load_balancers do
      scope module: 'load_balancers' do
        resources :deploy_load_balancer
      end
    end

    resources :lets_encrypt do
      scope module: 'lets_encrypt' do
        resources :lets_encrypt_auth
      end
    end

    resources :networks do
      scope module: 'networks' do
        resources :ip_addresses
      end
    end

    resources :nodes do
      scope module: 'nodes' do
        resources :events
      end
    end

    resources :products do
      scope module: 'products' do
        resources :billing_packages
      end
    end

    resources :regions do
      scope module: 'regions' do
        resources :nodes
      end
    end

    namespace :settings do
      resources :billing_module
    end
    resources :settings

    resources :sftp do
      scope module: 'sftp' do
        resources :events, :password, :power, :remote_volumes
      end
    end

    resources :subscriptions do
      scope module: 'subscriptions' do
        delete 'subscription_usage', to: 'subscription_usage#destroy'
        resources :subscription_events, :subscription_products, :subscription_usage
      end
    end

    resources :users do
      scope :module => 'users' do
        post 'bypass_second_factor' => 'bypass_security#create'
        delete 'bypass_second_factor' => 'bypass_security#destroy'
        resources :container_services, :event_logs, :subscriptions, :whois
      end
    end

    resources :volumes do
      scope module: 'volumes' do
        resources :backups, :charts, :clone, :logs, :restore, :subscribers
      end
    end

    get 'search' => 'search#new'
    post 'search' => 'search#create'

    ##
    # Standard Resources
    resources :alert_notifications,
              :app_events,
              :audit,
              :container_domains,
              :dashboard,
              :event_logs,
              :lets_encrypt,
              :locations,
              :orders,
              :system_events,
              :system_notifications,
              :user_groups

  end

  authenticated :user, -> user { user.is_admin } do
    mount Sidekiq::Web => '/queue'
  end

end
