Rails.application.routes.draw do
  namespace :api do
    namespace :system do
      # resources :ingress_rules, only: [ :index ]
      resources :alert_notifications
      # Agent event ingest (POST) retired in the Consul→cs-agent migration; the task
      # reconciler now creates/correlates events. Only the API read surface + status
      # update remain.
      resources :events, only: %i[index show update]
      # Provisioner fetches a node's admin-token hash from the node itself; the node
      # is identified by its source IP, gated by NODE_ENROLLMENT_TOKEN.
      get "nodes/agent_token_hash", to: "agent_tokens#show"
    end
  end
end
