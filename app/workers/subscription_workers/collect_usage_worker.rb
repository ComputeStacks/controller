module SubscriptionWorkers
  class CollectUsageWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform
      BillingUsageServices::CollectUsageService.new.perform
    rescue => e
      ExceptionAlertService.new(e, 'f61fd912b5123e42').perform
    end

  end
end
