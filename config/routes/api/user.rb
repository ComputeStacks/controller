Rails.application.routes.draw do

  namespace :api do

    resources :containers do
      scope module: 'containers' do
        namespace :metrics do
          resources :cpu, :memory
        end
        resources :container_processes,
                  :logs,
                  :power
      end
    end

    resources :container_images do
      scope module: 'container_images' do
        resources :collaborators,
                  :custom_host_entries,
                  :env_params,
                  :image_relationships,
                  :ingress_params,
                  :setting_params,
                  :volume_params
      end
    end

    resources :container_services do
      scope module: 'container_services' do
        resources :bastions,
                  :containers,
                  :events,
                  :ingress_rules,
                  :host_entries,
                  :load_balancers,
                  :logs,
                  :metadata,
                  :power,
                  :resize,
                  :scale,
                  :ssl
      end
    end

    resources :domains do
      scope module: 'domains' do
        resources :verify_dns
      end
    end

    get 'event_logs/:id', :to => 'event_logs#show'

    resources :container_registry do
      scope module: 'container_registry' do
        resources :collaborators
      end
    end

    resources :zones do
      scope module: 'zones' do
        resources :collaborators
      end
    end

    scope :networks do
      scope module: 'networks' do
        resources :ingress_rules do
          scope module: 'ingress_rules' do
            resources :domains, :toggle_nat
          end
        end
      end
    end

    resources :projects do
      scope module: 'projects' do
        resources :bastions do
          scope module: 'bastions' do
            resources :reset_password
          end
        end
        resources :containers, :collaborators, :events, :images, :services
      end
    end

    resources :subscriptions do
      scope module: 'subscriptions' do
        resources :billing_events, :billing_usages
      end
    end

    resources :volumes do
      scope module: 'volumes' do
        resources :backups, :restore
      end
    end

    get 'users', to: 'users#show'
    patch 'users', to: 'users#update'

    namespace :users do
      resources :ssh_keys
    end

    resources :container_image_providers,
              :collaborations,
              :load_balancers,
              :locations,
              :orders,
              :products,
              :users

  end

end
