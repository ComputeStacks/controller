Rails.application.routes.draw do

  resources :container_images do
    scope module: 'container_images' do
      resources :collaborators,
                :custom_host_entries,
                :env_params,
                :image_plugins,
                :image_collections,
                :image_relationships,
                :image_validation,
                :image_variants,
                :ingress_params,
                :setting_params,
                :volume_params
    end
  end

  resources :containers do
    scope module: 'containers' do
      get 'charts' => 'charts#index'
      namespace :charts do
        get 'cpu' => 'cpu#index'
        get 'cpu/throttled' => 'cpu#throttled', as: :cpu_throttled
        get 'disk' => 'disk_usage#index', as: :disk_usage
        get 'memory' => 'memory#index'
        get 'memory/throttled' => 'memory#throttled', as: :memory_throttled
        get 'memory/swap' => 'memory#swap', as: :memory_swap
        get 'network' => 'network#index'
        get 'load_balancer' => 'load_balancer#index'
        get 'load_balancer/sessions' => 'load_balancer#sessions', as: :load_balancer_sessions
      end
      resources :alerts, :container_logs, :power_management
    end
  end

  resources :container_services do
    scope module: 'container_services' do
      get 'charts' => 'charts#index'
      namespace :charts do
        get 'cpu' => 'cpu#index'
        get 'cpu/throttled' => 'cpu#throttled', as: :cpu_throttled
        get 'memory' => 'memory#index'
        get 'memory/throttled' => 'memory#throttled', as: :memory_throttled
        get 'memory/swap' => 'memory#swap', as: :memory_swap
        get 'network' => 'network#index'
        get 'load_balancer' => 'load_balancer#index'
        get 'load_balancer/sessions' => 'load_balancer#sessions', as: :load_balancer_sessions
      end
      get 'auto_scale' => 'auto_scale#edit'
      put 'auto_scale' => 'auto_scale#update'
      resources :ingress do
        scope module: 'ingress_rules' do
          resources :toggle_nat
        end
      end
      get 'events/last_event' => 'events#last_event'
      namespace :wordpress do
        delete 'protect' => 'protect#destroy'
        resources :protect, :sso, :users
      end
      resources :alerts, :connect, :containers, :events, :environmental, :host_entries, :monarx, :resize_service, :service_logs, :scale_service, :settings
    end
  end

  resources :container_domains do
    scope module: 'container_domains' do
      resources :dns_check
    end
  end

  resources :container_registry do
    scope module: 'container_registry' do
      resources :collaborators, :registry_connect
    end
  end

  namespace :deployments do
    get 'orders/confirm' => 'orders#confirm'
    post 'orders/containers' => 'orders#add_containers'
    put 'orders/containers' => 'orders#update_containers'
    get 'orders/cancel' => 'orders#cancel'
    resources :orders
  end

  resources :deployments do
    scope module: 'deployments' do
      get 'sftp/:id/password', to: 'sftp#show'
      get 'services', to: 'services#index'
      get 'events/last_event' => 'events#last_event'
      post 'connection_helper/:id' => 'connection_helper#create'
      resources :certificates,
                :clone_project,
                :collaborators,
                :domains,
                :events,
                :notification_rules,
                :project_logs,
                :sftp,
                :ssh_keys,
                :upgrade,
                :volumes
    end
  end

  resources :volumes do
    scope module: 'volumes' do
      resources :backups, :charts, :logs, :restore, :subscribers
    end
  end

  resources :certificates, :container_image_collections

end
