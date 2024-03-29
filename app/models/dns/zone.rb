##
# Dns Zone
#
# To delete a zone without deleting it from the remote server,
# simply run `destroy` on the object from the console.
#
# Remote zones are not deleted as a callback, and destroy won't remove them.
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute name
#   @return [String]
#
# @!attribute user
#   @return [User]
#
# @!attribute dns_zone_collaborators
#   @return [Array<Dns::ZoneCollaborator>]
#
# @!attribute collaborators
#   @return [Array<User>]
#
class Dns::Zone < ApplicationRecord

  # saved_state:text # Marshal.dump/load
  # saved_state_ts:datetime # last updated.
  #
  # TODO: Should we lock the zone when editing? (only for Deployments)

  include Auditable
  include Authorization::DnsZone
  include RemoteZone

  scope :sorted, -> { order(:name) }

  belongs_to :user, optional: true

  has_many :dns_zone_collaborators, class_name: 'Dns::ZoneCollaborator', foreign_key: 'dns_zone_id'
  has_many :collaborators, through: :dns_zone_collaborators, source: :collaborator

  validates :name, uniqueness: true
  validate :domain_validator

  after_create_commit :refresh_user_quota

  before_destroy :clean_collaborators
  after_destroy :refresh_user_quota

  ##
  # Manage State for provisioners that use 'update_by_zone'.
  # By default, it will return the current client.
  def state_load!
    return self.client if self.saved_state.nil? || !available_actions.include?('update_by_zone')
    Marshal.load(self.saved_state)
  end

  # Data = updated client.
  def state_save!(data)
    return false unless available_actions.include?('update_by_zone')
    self.update(
      saved_state: Marshal.dump(data),
      saved_state_ts: Time.now.utc
    )
  end

  def content_variables
    {
      "user" => user&.full_name,
      "domain" => name
    }
  end

  class << self

    def valid_domain?(name)
      has_dot = name.strip.split('').last == '.'
      name = name.slice(0..-2) if has_dot
      if (name =~ /^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,15}$/).nil?
        return false
      end
      # Allow `.local` outside of production.
      unless Rails.env.production?
        return true if name.strip.split('.').last == "local"
      end
      !DomainPrefix.registered_domain(name).nil?
    end

    ##
    # Ensure zone does not already exist.
    # Admins can bypass by checking run_module_create.
    def name_available?(zone)
      dns_type = ProductModule.find_by(name: 'dns')
      if dns_type.nil?
        dns_type = ProductModule.create!(name: 'dns')
      end
      pd = dns_type.default_driver
      auth_client = pd.host_settings['auth_type'] == 'user' ? auth.client : pd.service_client
      z = zone.strip[-1] == '.' ? zone : "#{zone}."
      pd.zone.find(auth_client, z).nil?
    rescue => e
      SystemEvent.create!(
        message: "Error connecting to dns server",
        log_level: 'warn',
        data: { error: e.message },
        event_code: "32ccbcb57ad99d4c"
      )
      false
    end

    def sync!
    #   dns_type = ProductModule.find_by(name: 'dns')
    #   if dns_type.nil?
    #     dns_type = ProductModule.create!(name: 'dns')
    #   end
    #   dns_type.provision_drivers.each do |pd|
    #     next if pd.host_settings['auth_type'] == 'master' # No way to sync!
    #     User.all.each do |user|
    #       domains = []
    #       user.auths.each do |auth|
    #         domains << auth.client.user.domains
    #       end
    #       domains.flatten!
    #       domains.each do |d|
    #         check = Dns::Zone.where(name: d.name).first
    #         if check.nil?
    #           user.dns_zones.create!({name: d.name, provider_ref: d.id})
    #         end
    #       end
    #     end
    #   end
    #   true
    # rescue => e
    #   SystemEvent.create!(
    #     message: "PowerDNS Error",
    #     log_level: 'warn',
    #     data: {
    #       'error' => e.message
    #     }
    #   )
    #   false
    end

  end

  def self.load_all(all = false)
    dns_type = ProductModule.where(name: 'dns').first
    dns_type = ProductModule.create!(name: 'dns') if dns_type.nil?
    result = []
    dns_type.provision_drivers.each do |pd|
      rsp = pd.zone.list_all_zones(pd.service_client)
      rsp.each do |i|
        if all
          result << i
        else
          name_simple = i.id.strip[-1] == '.' ? i.id.strip[0..-2] : i.id.strip
          check = Dns::Zone.where(
              "provision_driver_id = ? AND (provider_ref = ? OR provider_ref = ?)",
              pd.id,
              name_simple,
              "#{i.id}."
          ).exists?
          result << i unless check
        end
      end
    end
    result.flatten
  rescue Pdns::AuthenticationFailed
    SystemEvent.create!(
        message: "PowerDNS Authentication Failure",
        log_level: 'warn',
        data: {},
        event_code: '75ee4101df14dce2'
    )
    []
  rescue => e
    ExceptionAlertService.new(e, '394121fbd82ff037').perform
    SystemEvent.create!(
        message: "DNS Error",
        log_level: 'warn',
        data: {
            'error' => e.message
        },
        event_code: '394121fbd82ff037'
    )
    []
  end

  private

  def domain_validator
    unless Dns::Zone.valid_domain?(name)
      errors.add(:name, "Not a valid domain name.")
    end
    return if ActiveRecord::Type::Boolean.new.cast(skip_provision_driver)
    return unless ActiveRecord::Type::Boolean.new.cast(run_module_create)
    return unless name_changed?
    unless Dns::Zone.name_available?(name)
      errors.add(:name, "already exists")
    end
  end

  def refresh_user_quota
    user.current_quota(true) if user
  end

  def clean_collaborators
    return if dns_zone_collaborators.empty?
    if user_performer.nil?
      errors.add(:base, "Missing user performing delete action.")
      return
    end
    dns_zone_collaborators.each do |i|
      i.current_user = user_performer
      unless i.destroy
        errors.add(:base, %Q(Error deleting collaborator #{i.id} - #{i.errors.full_messages.join("\n")}))
      end
    end
  end

end
