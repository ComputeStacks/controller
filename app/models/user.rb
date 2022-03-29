##
# User
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute active
#   @return [Boolean]
#
# @!attribute address1
#   @return [String]
#
# @!attribute address2
#   @return [String]
#
# @!attribute city
#   @return [String]
#
# @!attribute company_name
#   @return [String]
#
# @!attribute comments
#   @return [String]
#
# @!attribute confirmation_sent_at
#   @return [DateTime]
#
# @!attribute country
#   @return [String]
#
# @!attribute currency
#   @return [String]
#
# @!attribute current_sign_in_at
#   @return [DateTime]
#
# @!attribute current_sign_in_ip
#   @return [String]
#
# @!attribute email
#   @return [String]
#
# @!attribute external_id
#   @return [String]
#
# @!attribute failed_attempts
#   @return [Integer]
#
# @!attribute fname
#   @return [String]
#
# @!attribute labels
#   @example current labels in use
#     {
#       cpanel: {
#         provider_server => provider_username
#       },
#       kind: user|service_account
#     }
#   @return [Hash]
#
# @!attribute last_request_at
#   @return [DateTime]
#
# @!attribute last_request_ip
#   @return [String]
#
# @!attribute last_sign_in_at
#   @return [DateTime]
#
# @!attribute last_sign_in_ip
#   @return [String]
#
# @!attribute lname
#   @return [String]
#
# @!attribute locale
#   @return [String]
#
# @!attribute locked_at
#   @return [DateTime]
#
# @!attribute phase_started
#   @return [DateTime]
#
# @!attribute phone
#   @return [String]
#
# @!attribute reset_password_sent_at
#   @return [DateTime]
#
# @!attribute sign_in_count
#   @return [Integer]
#
# @!attribute state
#   @return [String]
#
# @!attribute timezone
#   @return [String]
#
# @!attribute user_group
#   @return [UserGroup]
#
# @!attribute vat
#   @return [String]
#
# @!attribute zip
#   @return [String]
#
# @!attribute created_at
#   @return [DateTime]
#
# @!attribute updated_at
#   @return [DateTime]
#
# @!attribute audits
#   @return [Array<Audit>]
#
# @!attribute event_logs
#   @return [Array<EventLog>]
#
# @!attribute container_images
#   @return [Array<ContainerImage>]
#
# @!attribute container_registries
#   @return [Array<ContainerRegistry>]
#
# @!attribute registry_collaborations
#   @return [Array<ContainerRegistry>]
#
# @!attribute deployments
#   @return [Array<Deployment>]
#
# @!attribute project_collaborations
#   @return [Array<Deployment>]
#
# @!attribute service_collaborations
#   @return [Array<Deployment::ContainerService>]
#
# @!attribute project_image_collaborations
#   @return [Array<Deployment>]
#
# @!attribute dns_zones
#   @return [Array<Dns::Zone>]
#
# @!attribute domain_collaborations
#   @return [Array<Deployment::ContainerDomain>]
#
# @!attribute lets_encrypts
#   @return [Array<LetsEncrypt>]
#
# @!attribute orders
#   @return [Array<Order>]
#
# @!attribute security_keys
#   @return [Array<User::SecurityKey>]
#
# @!attribute container_services
#   @return [Array<Deployment::ContainerService>]
#
# @!attribute deployed_images
#   @return [Array<ContainerImage>]
#
# @!attribute image_collaborations
#   @return [Array<ContainerImage>]
#
# @!attribute sftp_containers
#   @return [Array<Deployment::Sftp>]
#
# @!attribute volumes
#   @return [Array<Volume>]
#
# @!attribute container_domains
#   @return [Array<Deployment::ContainerDomain>]
#
# @!attribute deployed_containers
#   @return [Array<Deployment::Container>]
#
# @!attribute alert_notifications
#   @return [Array<AlertNotification>]
#
# @!attribute user_notifications
#   @return [Array<UserNotification>]
#
# @!attribute ssh_keys
#   @return [Array<UserSshKey>]
#
# @!attribute c_sftp_pass
#   Whether or
#   @return [Boolean]
#
class User < ApplicationRecord

  # Do not place below any other items. We need this defined first.
  belongs_to :user_group
  before_validation :set_user_group

  include Auditable
  include UserCanDo
  include SupportUser
  include UrlPathFinder
  include UserTwoFactor

  include Users::AccessControl
  include Users::AppEvent
  include Users::BillingDatum
  include Users::LegacyRemote
  include Users::OtpStorable


  scope :sorted, -> { order( Arel.sql("lower(users.lname), lower(users.fname)") ) }
  scope :by_last_name, -> { order( Arel.sql("lower(lname)") ) }
  scope :with_active_subscriptions, -> { select( Arel.sql("lower(users.lname), lower(users.fname), users.*") ).where(subscriptions: { active: true }).joins(:subscriptions).distinct }
  scope :cpanel, -> { where("labels::jsonb ? 'cpanel'") }
  scope :admins, -> { where is_admin: true }

  has_many :audits, dependent: :destroy
  has_many :event_logs, -> { distinct}, through: :audits

  has_many :container_images, dependent: :destroy
  has_many :container_registries, dependent: :destroy

  has_many :container_registry_collaborators, -> { where("container_registry_collaborators.active = true") }, foreign_key: 'user_id'
  has_many :registry_collaborations, through: :container_registry_collaborators, source: :container_registry

  has_many :deployments, dependent: :destroy

  has_many :deployment_collaborators, -> { where("deployment_collaborators.active = true") }, foreign_key: 'user_id'
  has_many :project_collaborations, through: :deployment_collaborators, source: :deployment
  has_many :service_collaborations, through: :deployment_collaborators, source: :container_services
  # This is different from `image_collaborations`. These are images related to a project this user is collaborating on.
  has_many :project_image_collaborations, through: :deployment_collaborators, source: :container_images


  has_many :dns_zones, class_name: 'Dns::Zone', dependent: :destroy
  has_many :domain_collaborators, -> { where("dns_zone_collaborators.active = true") }, class_name: 'Dns::ZoneCollaborator', foreign_key: 'user_id'
  has_many :domain_collaborations, through: :domain_collaborators, source: :dns_zone

  has_and_belongs_to_many :features

  # @return [Array<LetsEncrypt>]
  has_many :lets_encrypts

  has_many :orders, dependent: :destroy
  has_and_belongs_to_many :regions

  has_many :security_keys, class_name: 'User::SecurityKey', dependent: :destroy

  has_many :container_services, through: :deployments, source: :services

  has_many :deployed_images, through: :container_services, source: :container_image

  has_many :container_image_collaborators, -> { where("container_image_collaborators.active = true") }, foreign_key: 'user_id'
  has_many :image_collaborations, through: :container_image_collaborators, source: :container_image

  has_many :sftp_containers, through: :deployments
  has_many :volumes, dependent: :destroy
  has_many :container_domains, class_name: 'Deployment::ContainerDomain', dependent: :destroy
  has_many :load_balancers, -> { distinct }, through: :container_services

  has_many :deployed_containers, through: :deployments

  has_many :alert_notifications, through: :deployed_containers

  # Notification settings, user level.
  has_many :user_notifications, dependent: :destroy

  has_many :ssh_keys, class_name: 'UserSshKey', dependent: :destroy

  # has_and_belongs_to_many :event_logs

  # **Attr Accessors**
  # current_password
  # gen_sso_creds: Whether or not to generate SSO credentials on create
  # skip_remote
  # tmp_updated_password: Temporarily store new password for updating remotes in callback

  before_validation :try_selected_email!, if: :requested_email

  before_validation :check_current_password, if: :current_password

  attr_accessor :current_password, :gen_sso_creds, :skip_remote, :tmp_updated_password, :skip_email_confirm, :merge_labels, :requested_email

  # Ensure all currencies are in the format: 'USD'
  before_validation(on: [:create, :update]) do
    self.currency = self.currency.upcase if self.currency
  end

  before_save :combine_labels

  validates :fname, presence: true
  validates :lname, presence: true
  validates :email, presence: true, uniqueness: true
  validate :user_address, on: :create

  validates_with UserValidator

  # After commit process. Order is important!
  after_commit :user_webooks, on: %i[ create update ] # Webooks + Billing remote

  before_create :set_defaults
  before_destroy :safe_to_destroy?, prepend: true

  before_destroy :clean_collaborations, prepend: true

  after_create :process_billing_create_hooks
  after_update :process_billing_update_hooks

  def avatar_url(size = 80)
    "https://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(email)}?s=#{size}&d=robohash"
  end

  def tz
    timezone.to_s == "" ? "UTC" : timezone
  end

  def full_name
    "#{fname} #{lname}"
  end

  def full_name_with_id
    "#{full_name} (#{id})"
  end

  def is_service_account?
    labels['kind'] == 'service_account'
  end

  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  def locale_sym
    locale.blank? ? I18n.default_locale : locale.to_sym
  end

  ##
  # Find all users by search param
  #
  # This will take a given search param and find by:
  # * email
  # * fname
  # * lname
  # * first & lname combined
  #
  def self.search_by(q)
    result = []
    raw_data = ActiveRecord::Base.connection.execute(%Q(
      SELECT *
      FROM (
        SELECT id,email,fname,lname,fname || ' ' || lname AS fullname
        FROM users
      ) t
      WHERE lower(email) ~ '#{q}' OR lower(fname) ~ '#{q}' OR lower(lname) ~ '#{q}' OR lower(fullname) ~ '#{q}'
    ))
    raw_data.each do |i|
      u = User.find_by(id: i['id'])
      result << u unless u.nil? || result.include?(u)
    end
    result
  end

  private

  ##
  # =Process remote hooks
  #
  # This will call any admin webhooks, plus notify the billing module.
  #
  # Currently processing changes on:
  # * Password
  # * Name
  # * Email
  # * Address
  # * API
  # * Admin flag
  #
  def user_webooks
    watched_attr = Set[
        'fname', 'lname', 'email', 'encrypted_password', 'currency',
        'is_admin', 'api_key', 'country', 'city',
        'state', 'address1', 'address2', 'zip'
    ]
    have_attr = self.previous_changes.keys.to_set
    if watched_attr.intersect?(have_attr) && !is_support_admin?
      WebHookJob.perform_later(self) unless Setting.webhook_users.value.blank?
    end
  end

  def user_address
    if Setting.billing_address && !is_support_admin?
      errors.add(:country, 'must be present') if self.country.to_s.blank?
      if self.state.to_s.blank? && %w(US CA).include?(self.country.to_s)
        errors.add(:state, 'must be present')
      end
      errors.add(:address1, 'must be present') if self.address1.to_s.blank?
      errors.add(:city, 'must be present') if self.city.to_s.blank?
      if Setting.billing_phone
        if self.phone.blank?
          errors.add(:phone, 'must be present')
        elsif self.phone.length < 7 || self.phone.length > 16
          errors.add(:phone, 'must be between 8 and 15 digits')
        end
      end
    else
      self.country = "US" if self.country.blank?
    end
  end

  def set_defaults
    if self.token.nil?
      self.token = SecureRandom.uuid
    end
    if self.gen_sso_creds
      self.auth_token = SecureRandom.urlsafe_base64(24)
      self.auth_token_exp = 10.minutes.from_now
    end
    self.webauthn_id = WebAuthn.generate_user_id if webauthn_id.blank?
  end

  def safe_to_destroy?
    errors.add(:base, 'Unable to delete an admin. Please remove the admin role first.') if is_admin
    errors.add(:base, "Please delete all Deployments first") unless deployments.empty?
    errors.add(:base, "Please remove all Volumes first") unless volumes.empty?
  end

  def set_user_group
    if self.user_group.nil?
      default_group = UserGroup.find_by(is_default: true)
      self.user_group = default_group if default_group
    end
  end

  def process_billing_create_hooks
    return true if is_admin
    if Setting.billing_hooks.include? :user_created
      Setting.call_billing_hook :user_created, self
    end
  end

  def process_billing_update_hooks
    return true if is_admin
    if Setting.billing_hooks.include? :user_updated
      Setting.call_billing_hook :user_updated, self
    end
  end

  ##
  # Insert top level key into existing labels hash
  def combine_labels
    if merge_labels && merge_labels.kind_of?(Hash)
      merge_labels.each_key do |i|
        labels[i] = merge_labels[i]
      end
    end
  end

  def try_selected_email!
    return if requested_email.blank?
    return if email == requested_email
    self.skip_confirmation!
    if User.where(email: requested_email).exists?
      suffix = "@#{Setting.app_name.parameterize}.local"
      choice_one = "#{fname.downcase}.#{lname.downcase}#{suffix}"
      self.email = User.where(email: choice_one).exists? ? "#{SecureRandom.uuid}#{suffix}" : choice_one
    else
      self.email = requested_email
    end
    self.requested_email = nil
  end

  def check_current_password
    return if current_password.blank?
    unless valid_password? current_password
      errors.add(:base, 'current password is invalid')
    end
  end

  ##
  # Clean collaborations prior to deleting
  #
  # relations will be scoped to active,
  # we want to remove all including pending
  def clean_collaborations
    return unless current_user
    ContainerImageCollaborator.where(user_id: id).each do |i|
      i.current_user = current_user
      i.skip_confirmation = true
      i.destroy
    end
    ContainerRegistryCollaborator.where(user_id: id).each do |i|
      i.current_user = current_user
      i.skip_confirmation = true
      i.destroy
    end
    DeploymentCollaborator.where(user_id: id).each do |i|
      i.current_user = current_user
      i.skip_confirmation = true
      i.destroy
    end
    Dns::ZoneCollaborator.where(user_id: id).each do |i|
      i.current_user = current_user
      i.skip_confirmation = true
      i.destroy
    end
  end

end
