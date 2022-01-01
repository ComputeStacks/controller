module RemoteZone
  extend ActiveSupport::Concern

  included do

    belongs_to :provision_driver, optional: true
    has_one :auth, ->(zone) { where user_id: zone.user_id }, through: :provision_driver, source: :auths

    before_create :set_provision_driver
    around_save :module_create!

    after_update_commit :apply_commitments

    attr_accessor :soa_email, :commit_changes, :revert_changes, :run_module_create, :skip_provision_driver
  end

  def client
    auth_client = provision_driver.host_settings['auth_type'] == 'user' ? auth.client : provision_driver.service_client
    # TODO: Go back and look at how settings & Configuration is saved here in ComputeStacks.
    # if provision_driver.settings['config'] && provision_driver.module_name != 'Onapp'
    #   eval("#{provision_driver.module_name}").configure(provision_driver.settings['config'])
    # end
    remote_zone = provision_driver.zone.find(auth_client, provider_ref)
    if remote_zone.nil?
      remote_zone = provision_driver.zone.new(auth_client, provider_ref)
      remote_zone.name = self.name
    end
    remote_zone
  rescue => e
    ExceptionAlertService.new(e, '14190c36e13b300a').perform
    raise 'Unable to connect to DNS Provider.'
  end

  def allow_owner_change?
    provision_driver.host_settings['auth_type'] == 'master'
  rescue => e
    ExceptionAlertService.new(e, '8f5e7ad16a56fee9').perform
    false
  end

  # uninitialized constant Dns::Zone::ConnectionBlocked
  def module_delete!
    client.destroy if self.provision_driver
  rescue => e
    ExceptionAlertService.new(e, '1b2b214a20e699fd').perform
    {'success' => false, 'message' => e.to_s}
  else
    {'success' => true}
  ensure
    self.destroy
  end

  def available_actions
    self.provision_driver.module_settings.available_actions['dns']
  rescue => e
    ExceptionAlertService.new(e, '1b878f927ac8c9a2').perform
    []
  end

  def apply_commitments
    return nil if self.provision_driver.nil?
    if ActiveRecord::Type::Boolean.new.cast(self.commit_changes)
      state_commit!
    elsif ActiveRecord::Type::Boolean.new.cast(self.revert_changes)
      state_revert!
    end
  end

  def module_create!
    if self.run_module_create.nil?
      # nil = do nothing.
    elsif self.provision_driver.nil?
      # Also do nothing..no provision driver.
    elsif ActiveRecord::Type::Boolean.new.cast(self.run_module_create)
      dns_client = client
      module_client = dns_client
      module_client.name = self.name
      module_client.id = nil
      module_client.save
      if module_client.errors.empty? && module_client.id
        self.provider_ref = module_client.id
      else
        errors.add(:base, module_client.errors.join(' '))
      end
    else
      # If we're not running the create command, make sure we have provider_ref set.
      self.provider_ref = self.name if self.provider_ref.blank?
    end
    yield
  rescue => e
    ExceptionAlertService.new(e, '80183586f634eb12').perform
    errors.add(:base, e.message)
  end

  def set_provision_driver
    return nil if ActiveRecord::Type::Boolean.new.cast(self.skip_provision_driver)
    if self.provision_driver_id.nil?
      dns_type = ProductModule.find_by(name: 'dns')
      if dns_type.nil?
        dns_type = ProductModule.create!(name: 'dns')
      end
      pd = dns_type.default_driver
      if pd.nil?
        errors.add(:base, "Missing DNS Provider.")
      else
        self.provision_driver = pd
      end
    end
  end

  # Commit the currently saved state to the provider.
  def state_commit!
    if self.saved_state.nil? || !available_actions.include?('update_by_zone')
      return {'success' => false, 'message' => 'Action not available.'}
    else
      begin
        zone = state_load!
        zone.save
      rescue => e
        ExceptionAlertService.new(e, '3f127f3a8388560f').perform
        {'success' => false, 'message' => e.message}
      else
        self.update_columns(saved_state: nil, saved_state_ts: nil)
        {'success' => true}
      end
    end
  end

  # Clears the current saved changes
  def state_revert!
    self.update_columns(saved_state: nil, saved_state_ts: nil)
  end

end
