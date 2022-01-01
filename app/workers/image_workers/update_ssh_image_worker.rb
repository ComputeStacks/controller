module ImageWorkers
  class UpdateSshImageWorker
    include Sidekiq::Worker

    sidekiq_options retry: 4, queue: 'low'

    def perform
      Node.online.each do |node|
        begin
          i = NodeServices::PullImageService.new(node)
          i.raw_image = Deployment::Sftp.new.image
          i.perform
        rescue => e
          ExceptionAlertService.new(e, '240e3f8d6557db3e').perform
          next
        end
      end
    end

  end
end
