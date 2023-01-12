module RegistryWorkers
  class ProvisionRegistryWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    def perform(registry_id)
      registry = ContainerRegistry.find_by id: registry_id
      return if registry.nil?

      registry.deploy!
    end

  end
end
