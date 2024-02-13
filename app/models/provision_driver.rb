## Provision Driver
#
# @deprecated Will soon completely remove the ProvisionDriver & ProductModule.
#             This is a relic of our previous Virtual Machine integration.
#             Currently, this is only used by our DNS integration.
#
# endpoint:string
# auth_type: static [future: oauth]
# module_type: ProductModule
# username:string
# api_key:string
# api_secret:string
#
# FEATURES:
# ptr -- Enable/Disable PTR / Reverse DNS
# selectable_regions -- Whether to specify the region_id during creation
#
class ProvisionDriver < ApplicationRecord

  scope :dns_drivers, -> { where("product_modules.name = 'dns'").joins(:product_modules) }
  has_many :dns_zones, class_name: 'Dns::Zone', dependent: :nullify

  has_many :auths, class_name: 'ProvisionDriver::UserAuth'
  has_many :regions, dependent: :destroy
  has_many :users, through: :user_auths

  has_and_belongs_to_many :product_modules

  serialize :settings, coder: JSON

  def virtual_machine
    eval("#{self.module_name}::VirtualMachine")
  end

  def template
    eval("#{self.module_name}::Template")
  end

  def snapshot
    eval("#{self.module_name}::Snapshot")
  end

  def firewall_rule
    eval("#{virtual_machine}::FirewallRule")
  end

  def features
    eval("#{self.module_name}::Settings").available_actions
  end

  def host_settings
    eval("#{self.module_name}::Settings").host_settings(service_client)
  end

  def cloud_user
    eval("#{self.module_name}::User")
  end

  def module_settings
    eval("#{self.module_name}::Settings")
  end

  # TODO: Figure out what this is for...we're not actually using the settings.
  def sync_settings!
    response = self.module_settings.host_settings(self.service_client)
    if response
      existing_settings = self.settings
      # Loop through everything so we dont update other settings.
      if response.kind_of?(Hash)
        response.each_key do |i|
          existing_settings[i] = response[i]
        end
      else
        # Unexpected response
        return true
      end
      self.update_attribute :settings, existing_settings
    end
  end

  # Will attempt to load all regions
  def load_regions!
    all_regions = self.module_settings.available_regions(self.service_client)
    all_regions.each do |i|
      existing_region = nil
      Region.all.each do |r|
        if r.name == i['label'] || r.settings['id'] == i['id']
          existing_region = r
        end
      end
      if existing_region.nil? && i['active']
        self.regions.create!(
            name: i['label'],
            active: i['active'],
            settings: i['settings'],
            features: i['features']
        )
      elsif existing_region && i['active']
        existing_region.update(
            settings: i['settings'],
            features: i['features']
        )
      end
    end
    # Set an initial default region.
    if self.regions.where(is_default: true).empty?
      self.regions.first.update_attribute :is_default, true
    end
    return "Driver now has #{self.regions.count} Regions."
  end

  def is_available?
    begin
      version = service_client.version
    rescue
      false
    else
      %w(Float Fixnum Integer).include?(version.class.to_s)
    end
  end

  def service_client
    eval("#{self.module_name}::Client").new(self.endpoint, cloud_auth)
  end

  def zone
    load_pd_config
    eval("#{self.module_name}::Dns::Zone")
  end

  def zone_record
    load_pd_config
    eval("#{self.module_name}::Dns::ZoneRecord")
  end

  def has_txt_limit?
    module_settings.has_txt_limit?
  end

  def support_dnssec?
    module_settings.supports_dnssec?
  end

  def require_soa_email?
    module_settings.require_email_on_create?
  end

  private

  def load_pd_config
    eval("#{self.module_name}").configure(settings['config']) if settings['config'] && !settings['config'].empty?
  end

  def cloud_auth
    eval("#{self.module_name}::Auth").new(0, self.username, self.api_key.nil? ? nil : Secret.decrypt!(self.api_key), self.api_secret.nil? ? nil : Secret.decrypt!(self.api_secret))
  end


end
