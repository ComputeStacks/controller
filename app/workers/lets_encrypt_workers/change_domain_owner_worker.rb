module LetsEncryptWorkers
  class ChangeDomainOwnerWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1, queue: "default"

    # This should be scheduled to run 5 minutes after a domain has changed hands
    # to ensure we're no longer tied to the previous owner's projects.
    def perform(container_domain_id)
      container_domain = Deployment::ContainerDomain.find_by(id: container_domain_id)
      return if container_domain.nil?

      cert = container_domain.lets_encrypt
      return if cert&.user.nil?
      return if cert.user == container_domain.user

      # If our cert has more than 1 domain, then migrate this domain
      # to a new one.
      if cert.container_domains.count > 1
        container_domain.update lets_encrypt_id: nil

        # Force selection or creation of a new certificate
        container_domain.lets_encrypt_init!
        return
      end

      cert.update user: container_domain.user
    rescue => e
      ExceptionAlertService.new(e, "457112771d98d47e").perform
    end
  end
end
