module ContainerWorkers
  class RefreshStatsWorker
    include Sidekiq::Worker

    sidekiq_options retry: false,
                    lock: :until_and_while_executing

    def perform

      Deployment::Container.all.each do |i|
        i.stats false
      end

    rescue => e
      ExceptionAlertService.new(e, '953ea854a6a7423b').perform
    end

  end
end
