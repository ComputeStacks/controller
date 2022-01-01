module LetsEncryptWorkers
  class ChangeDomainOwnerWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1, queue: 'default'

    # This should be scheduled to run 5 minutes after a domain has changed hands
    # to ensure we're no longer tied to the previous owner's projects.
    def perform(container_domain_id)
      container_domain = Deployment::ContainerDomain.find_by(id: container_domain_id)
      return if container_domain.nil?

      if container_domain.lets_encrypt
        if container_domain.lets_encrypt_user && (container_domain.lets_encrypt_user != container_domain.user)
          container_domain.update_column :lets_encrypt_id, nil
        end
      end
    rescue => e
      ExceptionAlertService.new(e, '457112771d98d47e').perform
    end

  end
end
