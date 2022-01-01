module SubscriptionWorkers
  class ProcessUsageWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform
      BillingUsageServices::AggregateUsageService.new.perform
    rescue => e
      ExceptionAlertService.new(e, '5196b85ddda2f171').perform
    end

  end
end
