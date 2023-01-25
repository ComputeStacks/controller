module MarketplaceWorkers
  class UsageWorker
    include Sidekiq::Worker

    sidekiq_options retry: 2, queue: 'low'

    def perform
      MarketplaceServices::BillingReporter.new.perform
    end

  end
end
