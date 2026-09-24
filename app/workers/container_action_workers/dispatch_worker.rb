module ContainerActionWorkers
  ##
  # Executes one projected action via its engine-registered handler. Deployment-
  # scoped work that makes an external HTTP call → `dep` queue (worker_deployments).
  class DispatchWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: "dep"

    def perform(id)
      req = ContainerActionRequest.find_by(id: id)
      return if req.nil?

      ContainerActionServices::Dispatch.new(req).call
    end
  end
end
