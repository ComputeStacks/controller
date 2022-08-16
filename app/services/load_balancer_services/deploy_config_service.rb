require 'sidekiq/api'
module LoadBalancerServices
  ##
  # Ensure only 1 LB job is queued
  #
  # @!attribute lb
  #   @return [LoadBalancer]
  # @!attribute queue_name
  #   @return [String]
  class DeployConfigService

    attr_accessor :lb,
                  :queue_name

    def initialize(lb = nil)
      self.lb = lb
      self.queue_name = 'default'
    end

    def perform
      return true unless existing_jobs.empty?
      LoadBalancerWorkers::DeployConfigWorker.perform_async(lb.nil? ? nil : lb.to_global_id.to_s)
    end

    private

    # TODO: Replace with `sidekiq-unique-jobs`
    def existing_jobs
      Sidekiq::Queue.new(queue_name).select do |i|
        if lb.nil?
          q1 = i.item['class'] == 'LoadBalancerWorkers::DeployConfigWorker'
          q2 = i.args.empty?
        else
          q1 = i.item['class'] == 'LoadBalancerWorkers::DeployConfigWorker'
          q2 = i.args.include? lb.to_global_id.to_s.to_s
        end
        q1 && q2
      end
    end

  end
end
