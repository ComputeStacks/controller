module ProjectServices
  ##
  # Clone a project
  #
  # This will create a new order with all the same images as a given project,
  # and will set all volumes to clone the volumes from the source project.
  #
  # Currently, this will _not_ migrate custom service environment variables (or settings),
  # nor will it copy over changes made to ingress rules or snapshot settings. Those will revert
  # to the source image.
  #
  # @!attribute project
  #   @return [Deployment]
  # @!attribute order_session
  #   @return [OrderSession]
  # @!attribute errors
  #   @return [Array]
  # @!attribute event
  #   @return [EventLog]
  # @!attribute current_audit
  #   @return [Audit]
  class CloneProjectService

    attr_accessor :project,
                  :order_session,
                  :errors,
                  :event,
                  :current_audit,
                  :user

    # @param [Deployment] project
    # @param [Audit] audit
    def initialize(project, audit)
      self.project = project
      self.current_audit = audit
      self.order_session = nil
      self.event = nil
      create_event! if current_audit
      self.user = current_audit.user if current_audit
      self.errors = []
    end

    def perform
      if event.nil?
        errors << "Missing event"
        return false
      end
      if user.nil?
        errors << "Missing user"
        return false
      end
      self.order_session = OrderSession.new user, nil
      order_session.skip_dep = true

      project.services.each do |i|
        vols = []
        i.volume_maps.each do |vm|
          vol_action = 'clone'
          vol_source = vm.volume.csrn
          unless vm.is_owner
            if vm.volume.template
              vol_action = 'mount'
              vol_source = vm.volume.template.csrn
            else
              event.event_details.create!(
                data: "Volume is not linked to template, unable to mount. Fallback to cloning.\n\nVolume: #{vm.volume.csrn} | Mount Path: #{vm.mount_path}",
                event_code: "7d625c910b4bf01d"
              )
            end
          end
          vols << {
            action: vol_action, source: vol_source, mount_path: vm.mount_path, mount_ro: vm.mount_ro
          }
        end
        order_session.add_image i.image_variant, { volume_overrides: vols, source: i.csrn }
      end
      # The previous should already have all dependencies. However, if the image has a new dependency, this will make
      # sure the order won't fail due to missing dependencies.
      order_session.add_dependencies!
      if order_session.nil?
        errors << "Missing order session"
      end
      order_session.save
    end

    private

    def create_event!
      self.event = EventLog.create!(
        locale: 'project.clone',
        locale_keys: {
          project: project.name
        },
        audit: current_audit,
        event_code: 'a3f3bb0ada9d90b9'
      )
      event.deployments << project
    end

  end
end
