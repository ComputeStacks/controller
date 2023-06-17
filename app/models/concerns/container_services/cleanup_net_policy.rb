module ContainerServices
  ##
  # Clean calico policies
  # Used by:
  #   * Deployment::Sftp
  #   * Deployment::ContainerService
  module CleanupNetPolicy
    extend ActiveSupport::Concern

    included do
      before_destroy :clean_net_policy!
    end

    private

    def clean_net_policy!
      return if deployment.nil?
      return unless deployment.private_network.nil?
      NetworkWorkers::TrashPolicyWorker.perform_async region.id, name
    end

  end
end
