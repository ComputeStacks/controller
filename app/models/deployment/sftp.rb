##
# SFTP Container
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute [r] name
#   @return [String]
#
# @!attribute node
#   @return [Node]
#
# @!attribute deployment
#   @return [Deployment]
#
# @!attribute pw_auth
#   @return [Boolean]
#
# @!attribute ingress_rules
#   @return [Array<Network::IngressRule>]
#
# @!attribute ip_address
#   @return [Network::Cidr]
#
# @!attribute event_logs
#   @return [Array<EventLog>]
#
# @!attribute ssh_host_keys
#   @return [Deployment::SftpHostKey]
#
# @!attribute alert_notifications
#   @return [Array<AlertNotification>]
#
class Deployment::Sftp < ApplicationRecord

  include Auditable
  include Authorization::Container
  include Containerized
  include Containers::ContainerNetworking
  include Containers::PowerManager
  include Containers::StateManager
  include Containers::SshVolumes
  include ContainerServices::CalicoServicePolicy
  include UrlPathFinder

  scope :sorted, -> { order(created_at: :desc) }

  scope :trashable, -> { where(to_trash: true) }
  scope :active, -> { where(to_trash: false) }

  belongs_to :load_balancer

  belongs_to :deployment, optional: true
  has_one :user, through: :deployment

  belongs_to :node
  has_one :region, through: :node
  has_one :location, through: :region

  has_many :ingress_rules, class_name: 'Network::IngressRule', foreign_key: 'sftp_container_id', dependent: :destroy
  has_one :ip_address, dependent: :destroy, class_name: 'Network::Cidr', foreign_key: 'sftp_container_id'
  has_one :network, through: :ip_address

  # @return [Array<EventLog>]
  has_and_belongs_to_many :event_logs, foreign_key: 'deployment_sftp_id'

  # @return [Array<EventLogDatum>]
  has_many :event_details, through: :event_logs

  has_many :alert_notifications, dependent: :destroy, foreign_key: 'sftp_container_id'

  has_many :ssh_host_keys, class_name: 'Deployment::SftpHostKey', dependent: :destroy, foreign_key: 'sftp_container_id'

  before_save :set_pass
  after_save :update_pw_auth!

  after_create :setup_ingress_rule!
  after_create :generate_certificates!
  after_create :set_ssh_auth!

  after_create_commit :init_metadata!

  attr_accessor :current_audit

  def toggle_pw_auth!
    pw_auth ? update(pw_auth: false) : update(pw_auth: true)
  end

  # Helper since we really only have 1 rule
  def ingress_rule
    ingress_rules.find_by proto: 'tcp'
  end

  def lb_proxy_name
    "sftp-#{id}"
  end

  def public_port
    ingress_rule.nil? ? 0 : ingress_rule.port_nat
  end

  def can_trash?
    to_trash
  end

  def image
    Rails.env.production? ? "cmptstks/ssh:v2" : "cmptstks/ssh:beta"
  end

  def reset_password!

  end

  def password
    return nil if password_encrypted.blank?
    Secret.decrypt!(password_encrypted)
  end

  def password=(data)
    self.password_encrypted = Secret.encrypt!(data)
  end

  def image_exists?
    return true if Docker::Image.exist?(self.image, {}, node.client)
    result = Docker::Image.create({'fromImage' => self.image}, nil, self.node.client)
    result.nil? ? false : true
  rescue
    false
  end

  ##
  # Remove the container and remove port forwarding
  def delete_now!(audit)
    c = self.docker_client
    return true if c.nil?
    c.stop
    c.delete
  rescue => e
    return true if e.message =~ /already in progress/
    ExceptionAlertService.new(e, '8d81bcafa05a4391').perform
    SystemEvent.create!(
      message: "Error deleting SFTP container: #{self.name}",
      log_level: 'warn',
      data: {
        'name' => self.name,
        'node' => self.node&.id,
        'error' => e.message
      },
      audit: audit,
      event_code: '8d81bcafa05a4391'
    )
    false
  else
    true
  ensure
    NetworkWorkers::TrashPolicyWorker.perform_async(region.id, name) if region
  end

  def build_command

    # Generate ingress rule
    setup_ingress_rule! if ingress_rule.nil?

    # Ensure we are able to get an IP
    return nil if local_ip.blank?

    return nil if deployment.nil?

    loki_labels = ['container_name={{.Name}}']
    loki_labels << "project_id=#{deployment.id}" if deployment

    mem_value = (512 * 1048576).to_i

    container = {
      'name' => name,
      'hostname' => name,
      'Domainname' => 'service.internal',
      'Image' => image,
      'Cmd' => ["sftpuser:#{password}:1001:1001:::apps"],
      'Env' => metadata_env_params.map { |k,v| "#{k}=#{v}" },
      'ExposedPorts' => {},
      'Labels' => {
        'org.projectcalico.label.token' => deployment.token,
        'org.projectcalico.label.service' => name,
        'com.computestacks.deployment_id' => deployment.id.to_s,
        'com.computestacks.image_name' => image
      },
      'HostConfig' => {
        'NetworkMode' => ip_address.network.name,
        'VolumeDriver' => 'local',
        'LogConfig' => log_driver_config,
        'PortBindings' => {},
        'Binds' => volume_binds,
        'NanoCPUs' => (0.5 * 1e9).to_i, # 1/2 Core
        'Memory' => mem_value,
        'MemorySwap' => mem_value
      },
      'NetworkingConfig' => {
        'EndpointsConfig' => {
          ip_address.network.name => {
            'IPAMConfig' => {
              'IPv4Address' => local_ip
            }
          }
        }
      }
    }
    if Rails.env.production?
      container['HostConfig']['ExtraHosts'] = ["metadata.internal:#{node.primary_ip}"]
    else
      container['HostConfig']['ExtraHosts'] = ["dev.computestacks.net:10.211.55.2", "metadata.internal:#{node.primary_ip}"]
    end
    container
  rescue ActiveRecord::RecordNotFound
    # Can happen if the SFTP container goes away during loading.
    return nil
  end

  def attached_to(quick = true)
    services = []
    self.volumes.each do |vol|
      next if vol['service'].nil?
      if quick
        services << deployment.services.select(:id, :name).find_by(name: vol['service'])
      else
        services << deployment.services.find_by(name: vol['service'])
      end
    end
    services
  end

  private

  def set_pass
    if password.blank?
      self.password = SecureRandom.urlsafe_base64(10).gsub("_", "").gsub("-", "")
    end
  end

  def setup_ingress_rule!
    if ingress_rule.nil?
      ir = ingress_rules.new(
        external_access: true,
        proto: 'tcp',
        port: 22,
        tcp_lb: false,
        skip_metadata_refresh: true
      )
      unless ir.save
        l = event_logs.create!(
          status: 'alert',
          notice: true,
          locale: 'deployment.errors.fatal',
          event_code: 'bdfb866183aec7cb',
          state_reason: 'Error tcp adding ingress rule'
        )
        l.event_details.create!(data: ir.errors.full_messages.join(" "), event_code: 'bdfb866183aec7cb')
        l.deployments << deployment if deployment
        l.users << user if user
        return nil
      end
    end
    ##
    # Add MOSH udp port. We will just mirror the nat port assigned to the tcp port.
    unless ingress_rules.where(proto: 'udp').exists?
      mosh = ingress_rules.new(
        external_access: true,
        proto: 'udp',
        port: ingress_rule.port_nat,
        port_nat: ingress_rule.port_nat,
        tcp_lb: false,
        skip_metadata_refresh: true
      )
      unless mosh.save
        l = event_logs.create!(
          status: 'alert',
          notice: true,
          locale: 'deployment.errors.fatal',
          event_code: 'ab92ad0c522620b2',
          state_reason: 'Error adding udp ingress rule'
        )
        l.event_details.create!(data: mosh.errors.full_messages.join(" "), event_code: 'ab92ad0c522620b2')
        l.deployments << deployment if deployment
        l.users << user if user
        return nil
      end
    end
  end

  def generate_certificates!
    unless ssh_host_keys.rsa.exists?
      ssh_host_keys.create!(algo: 'rsa')
    end
    unless ssh_host_keys.ed25519.exists?
      ssh_host_keys.create!(algo: 'ed25519')
    end
  end

  def set_ssh_auth!
    return unless user
    self.pw_auth = user.c_sftp_pass
  end

  def init_metadata!
    SftpServices::MetadataSshHostKeys.new(self).perform
  end

  def update_pw_auth!
    if pw_auth_previously_changed? && current_audit
      init_metadata!
      PowerCycleContainerService.new(self, 'restart', current_audit).perform
    end
  end

end
