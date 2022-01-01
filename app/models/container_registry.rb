##
# ContainerRegistry
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute user
#   @return [User]
#
# @!attribute name
#   @return [String]
#
# @!attribute label
#   @return [String]
#
# @!attribute status
#   @return [new,deploying,deployed,error,working]
#
# @!attribute endpoint
#   @return [String]
#
# @!attribute username
#   @return [String]
#
# @!attribute password
#   @return [String]
#
# @!attribute images
#   @return [Array<String>]
#
# @!attribute created_at
#   @return [DateTime]
#
# @!attribute created_at
#   @return [DateTime]
#
# @!attribute container_image_provider
#   @return [ContainerImageProvider]
#
# @!attribute containers
#   @return [Array<ContainerImage>]
#
# @!attribute deployed_containers
#   @return [Array<Deployment::Container>]
#
# @!attribute container_registry_collaborators
#   @return [Array<ContainerRegistryCollaborator>]
#
# @!attribute collaborators
#   @return [Array<User>]
#
class ContainerRegistry < ApplicationRecord

  include Auditable
  include Authorization::ContainerRegistry
  include MockRegistry

  belongs_to :user, optional: true

  has_one :container_image_provider, dependent: :delete # Avoid callbacks, which will prevent deletion.
  has_many :containers, through: :container_image_provider, source: :container_images, dependent: :restrict_with_error
  has_many :deployed_containers, through: :containers

  has_many :container_registry_collaborators
  has_many :collaborators, through: :container_registry_collaborators

  before_save :generate_password

  after_create :post_create

  after_create_commit :refresh_user_quota
  after_commit :update_provider, on: [:create, :update]

  after_destroy :refresh_user_quota

  before_destroy :clean_collaborators
  before_destroy :destroy_repo

  def registry_password
    return nil if password_encrypted.blank?
    Secret.decrypt!(password_encrypted)
  end

  def registry_password=(data)
    self.password_encrypted = Secret.encrypt!(data)
  end

  def name_with_user
    n = name
    n = "#{n}-#{label.strip}" unless label == name
    n = "#{n} (#{user.id}-#{user.email})" if user
    n
  end

  ## Generate list of images in this repository
  #
  # [
  #   {
  #     image: String,
  #     tags: [{
  #         tag: String,
  #         container: {
  #           id: Integer,
  #           name: String
  #         }
  #       }]
  #   }
  # ]
  def repositories
    return mock_repositories unless Rails.env.production?
    images = []
    base_url = "#{Setting.registry_base_url}:#{self.port}"
    return [] if registry_client.nil? # Means the client could not connect or authenticate with the registry
    begin
      client_images = registry_client.images
    rescue => e # Usually due to connection issues
      ExceptionAlertService.new(e, '7ce472ad3e09868c').perform
      SystemEvent.create!(
        message: "Container Registry Error",
        log_level: 'warn',
        data: {
          'registry' => {
            'id' => self.id,
            'user' => self.user&.email
          },
          'error' => e.message
        },
        event_code: '7ce472ad3e09868c'
      )
      return []
    end
    client_images.each do |i|
      next if i.tags.nil?
      next if i.tags['tags'].nil? || i.tags['tags'].empty? # dont show images with no tags, this means it's an empty repository.
      image = {image: i.image_name, tags: []}
      i.tags['tags'].each do |tag|
        container = nil
        container_check = container_image_provider.container_images.find_by(registry_image_path: i.image_name, registry_image_tag: tag)
        unless container_check.nil?
          container = {
            id: container_check.id,
            name: container_check.name
          }
        end
        image[:tags] << {
          tag: tag,
          container: container
        }
      end
      images << image
    end
    images
  end

  ## Building and deploying docker registry on physical host #####################################################################

  def deploy!
    return mock_deploy! unless Rails.env.production?
    self.update_column :status, 'deploying'
    container = docker_client
    if container.created?
      self.update_column :status, 'deployed'
      return true
    end
    if self.name.blank? # Extra safety around blank paths..
      self.update_column(:status, 'error')
      return false
    end
    container.client.exec!("mkdir -p /computestacks-mnt/#{self.name}/{auth,data}")
    container.exec!('htpasswd', "-Bbn admin #{registry_password} > /computestacks-mnt/#{self.name}/auth/htpasswd")
    container.create!
    update status: 'deployed'
  rescue => e
    ExceptionAlertService.new(e, '38db2d60875dcdf7').perform
    SystemEvent.create!(
      message: "Container Registry Error",
      log_level: 'warn',
      data: {
        'registry' => {
          'id' => self.id,
          'user' => self.user&.email
        },
        'error' => e.message
      },
      event_code: '38db2d60875dcdf7'
    )
    self.update_column :status, 'error'
  end

  # TODO: Look at adding 'REGISTRY_HTTP_SECRET'
  def docker_client
    set_port! if self.port.zero?
    container_env = [
      ['REGISTRY_AUTH', 'htpasswd'],
      ['REGISTRY_AUTH_HTPASSWD_PATH', '/auth/htpasswd'],
      ['REGISTRY_AUTH_HTPASSWD_REALM', "'Registry Realm'"],
      ['REGISTRY_STORAGE_DELETE_ENABLED', 'true']
    ]
    if Setting.registry_selinux
      # Add :Z for SELinux
      volumes = [
        ["/computestacks-mnt/#{self.name}/auth", '/auth:Z'],
        ["/computestacks-mnt/#{self.name}/data",'/var/lib/registry:Z']
      ]
    else
      volumes = [
        ["/computestacks-mnt/#{self.name}/auth", '/auth'],
        ["/computestacks-mnt/#{self.name}/data",'/var/lib/registry']
      ]
    end
    if Feature.check('updated_cr_cert')
      container_env << ['REGISTRY_HTTP_TLS_CERTIFICATE', "/certs/fullchain.pem"]
      container_env << ['REGISTRY_HTTP_TLS_KEY', "/certs/privkey.pem"]
      volumes << ["/opt/container_registry/ssl/", "/certs#{Setting.registry_selinux ? ':z' : ''}"]
    else # Legacy way of dealing with ContainerRegistry Certificates
      if Setting.computestacks_cr_le.value.nil?
        container_env << ['REGISTRY_HTTP_TLS_CERTIFICATE', '/certs/cert.cer']
        container_env << ['REGISTRY_HTTP_TLS_KEY', '/certs/key.pem']
        if Setting.registry_selinux
          volumes << ['/etc/ssl/container-registry', '/certs:z']
        else
          volumes << ['/etc/ssl/container-registry', '/certs']
        end
      else
        container_env << ['REGISTRY_HTTP_TLS_CERTIFICATE', "/certs/live/#{Setting.computestacks_cr_le.value}/fullchain.pem"]
        container_env << ['REGISTRY_HTTP_TLS_KEY', "/certs/live/#{Setting.computestacks_cr_le.value}/privkey.pem"]
        if Setting.registry_selinux
          volumes << ["/etc/letsencrypt", '/certs:z']
        else
          volumes << ["/etc/letsencrypt", '/certs']
        end
      end
    end
    ports = [[self.port, 5000]]
    options = {
      :env => container_env,
      :volumes => volumes,
      :port_map => ports,
      :restart_policy => "always"
    }
    params = {image_url: "cmptstks/registry:latest", settings: options, node: {key: ENV['CS_SSH_KEY']}}
    ssh_port = Setting.registry_ssh_port
    DockerSSH::Container.new(self.name, "ssh://#{Setting.registry_node}:#{ssh_port}", params)
  rescue => e
    ExceptionAlertService.new(e, '50da83a1ddcb0233').perform
    SystemEvent.create!(
      message: "Container Registry Connect Error",
      log_level: 'warn',
      data: {
        'registry' => {
          'id' => self.id,
          'user' => self.user&.email
        },
        'error' => e.message
      },
      event_code: '50da83a1ddcb0233'
    )
    nil
  end

  def registry_client
    c = DockerRegistry::Client.new(Setting.registry_base_url, self.port, {
      username: 'admin',
      password: registry_password
    })
    DockerRegistry::Repo.new(c)
  rescue => e
    ExceptionAlertService.new(e, 'eb77377c9ad9bcca').perform
    SystemEvent.create!(
      message: "Container Registry Auth Error",
      log_level: 'warn',
      data: {
        'registry' => {
          'id' => self.id,
          'user' => self.user&.email
        },
        'error' => e.message
      },
      event_code: 'eb77377c9ad9bcca'
    )
    nil
  end

  def set_port!
    ports_in_use = ContainerRegistry.all.pluck(:port)
    if Rails.env.production?
      p = 25000 # Temporary. Should eventually move back to 10,000.
    else
      p = 40000
    end
    while (ports_in_use.include?(p) && p < 50000) do
      p += 1
    end
    p > 49999 ? false : self.update_attribute(:port, p)
  end

  def content_variables
    {
      "user" => user&.full_name,
      "registry" => label
    }
  end

  ## END Building and deploying docker registry on physical host #################################################################
  private

  def destroy_repo
    return true if docker_client.nil?
    docker_client.stop
    docker_client.destroy
    docker_client.client.exec!("rm -rf /computestacks-mnt/#{self.name}") unless self.name.blank?
  end

  def post_create
    #port = rand(5000..20000)
    self.update({
      name: NamesGenerator.name(id),
      port: 0,
      label: label.blank? ? name : label
    })
  end

  def refresh_user_quota
    user.current_quota(true) if user
  end

  def update_provider

    if container_image_provider.nil?
      ContainerImageProvider.create!(
                              name: name,
                              is_default: false,
                              hostname: "#{Setting.registry_base_url}:#{port}",
                              container_registry_id: id

      )
    else
      container_image_provider.update(
        name: name,
        hostname: "#{Setting.registry_base_url}:#{port}"
      )
    end

  end

  def generate_password
    if registry_password.blank?
      self.registry_password = SecureRandom.urlsafe_base64(7).gsub("_","").gsub("-","")
    end
  end

  def clean_collaborators
    return if container_registry_collaborators.empty?
    if user_performer.nil?
      errors.add(:base, "Missing user performing delete action.")
      return
    end
    container_registry_collaborators.each do |i|
      i.current_user = user_performer
      unless i.destroy
        errors.add(:base, %Q(Error deleting collaborator #{i.id} - #{i.errors.full_messages.join("\n")}))
      end
    end
  end

end
