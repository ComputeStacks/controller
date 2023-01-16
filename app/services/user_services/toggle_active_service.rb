module UserServices
  ##
  # Activate/Deactivate Users
  #
  # @!attribute user
  #   @return [User]
  # @!attribute event
  #   @return [EventLog]
  class ToggleActiveService

    attr_accessor :user,
                  :event

    # @param [User] user
    # @param [Audit] audit
    def initialize(user, audit)
      self.user = user
      build_event(audit)
    end

    def perform
      event.start!
      user.active ? activate_user! : suspend_user!
      event.done!
      true
    rescue => e
      ExceptionAlertService.new(e, '653f400954df1fe3').perform
      event.event_details.create!(data: e.message, event_code: '653f400954df1fe3')
      event.fail! "Fatal Error"
      false
    end

    private

    def build_event(audit)
      self.event = EventLog.create!(
        locale: "users.#{user.active ? 'active' : 'inactive'}",
        locale_keys: { user: user.full_name },
        status: 'pending',
        audit: audit,
        event_code: '5e3f927694e5ae34'
      )
      event.users << user
      nil
    end

    def activate_user!
      user.deployed_containers.each do |container|
        container.subscription.unpause! if container.subscription
        PowerCycleContainerService.new(container, 'start', event.audit)
      end
      user.sftp_containers.each do |container|
        PowerCycleContainerService.new(container, 'start', event.audit)
      end
      ProcessAppEventWorker.perform_async 'UserActivated', nil, user.global_id
    end

    def suspend_user!
      user.deployed_containers.each do |container|
        PowerCycleContainerService.new(container, 'stop', event.audit)
        unless user.user_group.bill_suspended
          container.subscription.pause! if container.subscription
        end
      end
      user.sftp_containers.each do |container|
        PowerCycleContainerService.new(container, 'stop', event.audit)
      end
      ProcessAppEventWorker.perform_async 'UserSuspended', nil, user.global_id
    end

  end
end
