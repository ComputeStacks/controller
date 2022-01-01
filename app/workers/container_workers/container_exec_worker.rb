module ContainerWorkers
  class ContainerExecWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform(container_id, event_id, command = [])
      return if command.empty?
      container = GlobalID::Locator.locate container_id
      event = GlobalID::Locator.locate event_id

      return if container.nil? || event.nil?

      return unless event.start!

      container.container_exec!(command, event) unless Rails.env.test?
      event.done!
    rescue => e
      ExceptionAlertService.new(e, 'd55bc5f17b925a58').perform
    end

  end
end
