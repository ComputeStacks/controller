vagrant_vm_ip = `ip -j addr show dev eth0 | jq -r '.[0].addr_info | map(select(.family == "inet"))[0].local'`
puts "Creating default location and region..."
location = Location.create! name: "dev"

consul_token = File.exist?("/home/vagrant/consul.token") ? File.read("/home/vagrant/consul.token").gsub("\n","") : ""

region = location.regions.create! name: "dev", pid_limit: 150, ulimit_nofile_soft: 1024, ulimit_nofile_hard: 1024, consul_token: consul_token

puts "Creating system block content..."
puts "...Collaborate: Warning..."
block_collaborate = Block.create!(title: 'Collaborate: Warning', content_key: 'collaborate.warning')
block_collaborate.block_contents.create!(
  locale: ENV['LOCALE'],
  body: %Q(<div><strong>Warning!</strong> Any collaborator you add will have the same permissions as you!</div>)
)
block_faq = Block.create!(title: 'Collaborate: FAQ', content_key: 'collaborate.faq')
#noinspection RubyScope
block_faq.block_contents.create!(
  locale: ENV['LOCALE'],
  body: %Q(<div>Collaborators will be able to edit and manage this resource, as well as, create and delete any child resources. Any billable action they take will be billed to the resource owner's account.</div>)
)

puts "...Collaborate: Invitation - Registry..."
block_collaborate = Block.create!(title: 'Collaborate: Registry Invite', content_key: 'collaborate.invite.registry')
block_collaborate.block_contents.create!(
  locale: ENV['LOCALE'],
  body: %Q(<h4>Container Registry Collaboration Invite</h4><div>{{ user }} has invited you to collaborate on the container registry {{ registry }}. Please click the link below to accept or reject this invitation.</div>)
)

puts "...Collaborate: Invitation - Project..."
block_collaborate = Block.create!(title: 'Collaborate: Project Invite', content_key: 'collaborate.invite.project')
block_collaborate.block_contents.create!(
  locale: ENV['LOCALE'],
  body: %Q(<h4>Project Collaboration Invite</h4><div>{{ user }} has invited you to collaborate on the project {{ project }}. Please click the link below to accept or reject this invitation.</div>)
)

puts "...Collaborate: Invitation - Image..."
block_collaborate = Block.create!(title: 'Collaborate: Image Invite', content_key: 'collaborate.invite.image')
block_collaborate.block_contents.create!(
  locale: ENV['LOCALE'],
  body: %Q(<h4>Container Image Collaboration Invite</h4><div>{{ user }} has invited you to collaborate on the image {{ image }}. Please click the link below to accept or reject this invitation.</div>)
)

puts "...Collaborate: Invitation - DNS Zone..."
block_collaborate = Block.create!(title: 'Collaborate: DNS Zone Invite', content_key: 'collaborate.invite.domain')
block_collaborate.block_contents.create!(
  locale: ENV['LOCALE'],
  body: %Q(<h4>DNS Zone Collaboration Invite</h4><div>{{ user }} has invited you to collaborate on the zone {{ domain }}. Please click the link below to accept or reject this invitation.</div>)
)

puts "...Container Image: Domain..."
block_container_domain = Block.create!(title: 'Container Image: Domain Instructions', content_key: 'container_image.domain')
block_container_domain.block_contents.create!(
  locale: ENV['LOCALE'],
  body: "<h4>Connecting Your Domain</h4><div><br>All services are given a default URL to access your site.<br><br></div><div>To configure your own domain, please create A records for the following IP's:</div><div><br></div>"
)

puts "...Container Image: SSH..."
block_container_ssh = Block.create!(title: 'Container Image: SFTP', content_key: 'container_image.ssh')
block_container_ssh.block_contents.create!(
  locale: ENV['LOCALE'],
  body: "<h4>SFTP Access</h4><div><br>FTP access is provided through SFTP (SSH) with your included SSH bastion container.<br><br>Each SFTP container will mount the persistent volumes from your containers, allowing direct access to your files.<br><br>Additionally, this SFTP/SSH bastion container has access to the private network of your containers. You may use this to proxy over SSH and access your services without having to expose your containers to the public network.</div>"
)

puts "...Container Image: SSH Bastion..."
block_container_ssh = Block.create!(title: 'Container Image: SSH Bastion', content_key: 'container_image.ssh_bastion')
block_container_ssh.block_contents.create!(
  locale: ENV['LOCALE'],
  body: "<h4>SSH Bastion Access</h4><div><br>Each project is provided with at least 1 SSH bastion to allow direct access to your project's internal network. This bastion includes common linux tools to help with your application deployment process, as well as debugging any issues.</div>"
)

puts "...Container Image: Ports..."
block_container_remote = Block.create!(title: 'Container Image: Remote Access', content_key: 'container_image.ports')
block_container_remote.block_contents.create!(
  locale: ENV['LOCALE'],
  body: "<h4>Remote Access</h4><div><br></div><div>Each service is assigned a private IP that allows container-to-container communication within your project.<br>If you wish to connect directly to your service from outside your project, you will need to ensure <em>Remote Access</em> is enabled, and the load balancer needs to be set to <em>Global.</em><br><br>All traffic coming into your project will first pass through our&nbsp;<em>global load balancer&nbsp;</em>(Your public ip is the load balancer's IP address). From there, our load balancer will either directly connect to your service and perform standard round-robin load balancing, or it can connect to a custom load balancer defined by the container image.&nbsp;<br><br>For TCP services, you will receive an automatically generated port that will be dedicated to your service. You can optionally enable TLS on this for secure communication.</div>"
)

puts "...Email: Unlock..."
block_email_unlock = Block.create!(title: 'Email: Unlock Instructions', content_key: 'email.unlock')
block_email_unlock.block_contents.create!(
  locale: ENV['LOCALE'],
  body: "<div>Your account has been locked due to an excessive number of unsuccessful sign in attempts.<br>Click the link below to unlock your account:</div>"
)

puts "...Email: Password..."
block_email_password = Block.create!(title: 'Email: Password Reset', content_key: 'email.password')
block_email_password.block_contents.create!(
  locale: ENV['LOCALE'],
  body: "<div>Someone has requested a link to change your password. You can do this through the link below.<br>If you didn't request this, please ignore this email.<br>Your password won't change until you access the link above and create a new one.</div>"
)

puts "...Email: Confirmation..."
block_email_confirmation = Block.create!(title: 'Email: Confirmation', content_key: 'email.confirmation')
block_email_confirmation.block_contents.create!(
  locale: ENV['LOCALE'],
  body: "<div>You can confirm your email address and activate your account through the link below:</div>"
)

puts "Creating container image providers..."
puts "Creating DockerHub Image Provider..."
dh_provider = ContainerImageProvider.create!(
  name: "DockerHub",
  is_default: true,
  hostname: ""
)
puts "Creating Quay Image Provider..."
ContainerImageProvider.create!(
  name: "Quay",
  is_default: false,
  hostname: "quay.io"
)
puts "Creating Google Image Provider..."
ContainerImageProvider.create!(
  name: "Google",
  is_default: false,
  hostname: "gcr.io"
)
puts "Creating Elastic Image Provider..."
ContainerImageProvider.create!(
  name: "Elastic",
  is_default: false,
  hostname: "docker.elastic.co"
)
puts "Creating Github Image Provider..."
ContainerImageProvider.create!(
  name: "Github",
  is_default: false,
  hostname: "ghcr.io"
)

puts "Creating Container Images..."
puts "...Creating MariaDB 10.5...."
mysql = ContainerImage.create!(
  name: 'mariadb-105',
  label: 'MariaDB 10.5',
  role: 'mysql',
  role_class: 'database',
  can_scale: false,
  container_image_provider: dh_provider,
  registry_image_path: "mariadb",
  registry_image_tag: "10.5",
  command: "--max_allowed_packet=268435456",
  validated_tag: true,
  validated_tag_updated: Time.now
)
mysql.setting_params.create!(
  name: 'mysql_password',
  label: 'Root Password',
  param_type: 'password'
)
mysql.env_params.create!(
  name: 'MYSQL_ROOT_PASSWORD',
  label: 'MYSQL_ROOT_PASSWORD',
  param_type: 'variable',
  env_value: 'build.settings.mysql_password'
)
mysql.ingress_params.create!(
  port: 3306,
  proto: 'tcp',
  external_access: false
)
mysql.volumes.create!(
  label: 'mysql',
  mount_path: '/var/lib/mysql',
  enable_sftp: false,
  borg_enabled: true,
  borg_freq: '@daily',
  borg_strategy: 'mysql',
  borg_keep_hourly: 1,
  borg_keep_daily: 7,
  borg_keep_weekly: 4,
  borg_keep_monthly: 0
)

puts "...Creating Wordpress..."
wp = ContainerImage.create!(
  name: "wordpress",
  label: "Wordpress",
  description: "Wordpress powered by the OpenLiteSpeed web server. Includes advanced caching and performance tuning, with out of the box support for redis object cache (requires separate container).",
  role: "wordpress",
  role_class: "web",
  can_scale: true,
  container_image_provider: dh_provider,
  registry_image_path: "cmptstks/wordpress",
  registry_image_tag: "php7.4-litespeed",
  min_cpu: 1,
  min_memory: 512,
  labels: {
    system_image_name: "wordpress-litespeed"
  },
  validated_tag: true,
  validated_tag_updated: Time.now
)
wp.dependency_parents.create!(
  requires_container_id: mysql.id,
  bypass_auth_check: true
)
wp.setting_params.create!(
  name: 'wordpress_password',
  label: 'Password',
  param_type: 'password'
)
wp.setting_params.create!(
  name: 'litespeed_admin_pw',
  label: 'Litespeed Password',
  param_type: 'password'
)
wp.setting_params.create!(
  name: 'title',
  label: 'Title',
  param_type: 'static',
  value: 'My Blog'
)
wp.setting_params.create!(
  name: 'email',
  label: 'email',
  param_type: 'static',
  value: 'user@example.com'
)
wp.setting_params.create!(
  name: 'username',
  label: 'Username',
  param_type: 'static',
  value: 'admin'
)
wp.ingress_params.create!(
  port: 80,
  proto: 'http',
  external_access: true
)
wp.ingress_params.create!(
  port: 7080,
  proto: 'http',
  external_access: true,
  backend_ssl: true
)
wp.env_params.create!(
  name: 'LS_ADMIN_PW',
  param_type: 'variable',
  env_value: 'build.settings.litespeed_admin_pw'
)
wp.env_params.create!(
  name: 'WORDPRESS_DB_PASSWORD',
  param_type: 'variable',
  env_value: 'dep.mysql.parameters.settings.mysql_password'
)
wp.env_params.create!(
  name: 'WORDPRESS_DB_HOST',
  param_type: 'variable',
  env_value: 'dep.mysql.self.ip'
)
wp.env_params.create!(
  name: 'WORDPRESS_DB_NAME',
  param_type: 'variable',
  env_value: 'build.self.service_name_short'
)
wp.env_params.create!(
  name: 'WORDPRESS_URL',
  param_type: 'variable',
  env_value: 'build.self.default_domain'
)
wp.env_params.create!(
  name: 'WORDPRESS_TITLE',
  param_type: 'variable',
  env_value: 'build.settings.title'
)
wp.env_params.create!(
  name: 'WORDPRESS_USER',
  param_type: 'variable',
  env_value: 'build.settings.username'
)
wp.env_params.create!(
  name: 'WORDPRESS_PASSWORD',
  param_type: 'variable',
  env_value: 'build.settings.wordpress_password'
)
wp.env_params.create!(
  name: 'WORDPRESS_EMAIL',
  param_type: 'variable',
  env_value: 'build.settings.email'
)
wp.env_params.create!(
  name: 'WORDPRESS_DB_USER',
  param_type: 'static',
  static_value: 'root'
)
wp.volumes.create!(
  label: 'wordpress',
  mount_path: '/var/www',
  enable_sftp: true,
  borg_enabled: true,
  borg_freq: '@daily',
  borg_strategy: 'file',
  borg_keep_hourly: 1,
  borg_keep_daily: 7,
  borg_keep_weekly: 4,
  borg_keep_monthly: 0
)
wp.volumes.create!(
  label: 'webconfig',
  mount_path: '/usr/local/lsws',
  enable_sftp: false,
  borg_enabled: true,
  borg_freq: '@daily',
  borg_strategy: 'file',
  borg_keep_hourly: 1,
  borg_keep_daily: 7,
  borg_keep_weekly: 4,
  borg_keep_monthly: 0
)

puts "...Creating Redis..."
redis = ContainerImage.create!(
  label: 'Redis',
  name: 'redis',
  description: 'Redis in-memory key/value store. This image does not save data to disk.',
  role: 'redis',
  role_class: 'cache',
  can_scale: false,
  is_free: false,
  container_image_provider: dh_provider,
  registry_image_path: "redis",
  registry_image_tag: "alpine",
  labels: {
    system_image_name: "redis-public"
  },
  validated_tag: true,
  validated_tag_updated: Time.now
)
redis.ingress_params.create!(
  port: 6379,
  proto: 'tls',
  external_access: true
)
# Required for HA with NFS.
redis.volumes.create!(
  label: 'redis',
  mount_path: '/data',
  enable_sftp: false,
  borg_enabled: false
)

puts "...Creating phpMyAdmin..."
pma = ContainerImage.create!(
  name: "pma",
  label: "phpMyAdmin",
  description: "phpMyAdmin",
  role: "pma",
  role_class: "dev",
  is_free: true,
  can_scale: false,
  container_image_provider: dh_provider,
  registry_image_path: "cmptstks/phpmyadmin",
  registry_image_tag: "litespeed",
  validated_tag: true,
  validated_tag_updated: Time.now
)
pma.env_params.create!(
  name: 'BASE_URL',
  param_type: 'variable',
  env_value: 'region.endpoint.api'
)
pma.env_params.create!(
  name: 'HOSTNAME',
  param_type: 'variable',
  env_value: 'build.self.name'
)
pma.env_params.create!(
  name: 'API_URL',
  param_type: 'static',
  static_value: 'stacks/assets/pma'
)
pma.ingress_params.create!(
  port: 80,
  proto: 'http',
  external_access: true
)
pma.ingress_params.create!(
  port: 7080,
  proto: 'http',
  external_access: true,
  backend_ssl: true
)
pma.setting_params.create!(
  name: 'litespeed_admin_pw',
  label: 'Litespeed Password',
  param_type: 'password'
)
pma.env_params.create!(
  name: 'LS_ADMIN_PW',
  param_type: 'variable',
  env_value: 'build.settings.litespeed_admin_pw'
)
pma.volumes.create!(
  label: 'litespeed-config',
  mount_path: '/usr/local/lsws',
  enable_sftp: false,
  borg_enabled: false
)

puts "...Creating nginx..."
nginx = ContainerImage.create!(
  name: 'nginx',
  label: 'nginx',
  role: 'nginx',
  role_class: 'web',
  can_scale: true,
  container_image_provider: dh_provider,
  registry_image_path: "cmptstks/nginx",
  registry_image_tag: "stable",
  validated_tag: true,
  validated_tag_updated: Time.now
)
nginx.ingress_params.create!(
  port: 80,
  proto: 'http',
  external_access: true
)
nginx.volumes.create!(
  label: 'webroot',
  mount_path: '/var/www/html',
  enable_sftp: true,
  borg_enabled: true,
  borg_freq: '@daily',
  borg_strategy: 'file',
  borg_keep_hourly: 1,
  borg_keep_daily: 7,
  borg_keep_weekly: 4,
  borg_keep_monthly: 0
)

puts "Setting up billing products..."

plan = BillingPlan.create! name: 'default', is_default: true

# Container Package: Small
container_product = Product.create! name: 'small', label: 'Small', kind: 'package'
container_product.create_package cpu: 1, memory: 512, storage: 10, local_disk: 5, bandwidth: 500
container_product_resource = plan.billing_resources.create! product: container_product
container_product_resource.prices.create! price: 0.00343,
                                          currency: 'USD',
                                          billing_phase: container_product_resource.billing_phases.first,
                                          regions: Region.all

# Storage Product
storage_product = Product.create! name: 'storage',
                                  label: 'Storage',
                                  kind: 'resource',
                                  unit: 1,
                                  unit_type: 'GB',
                                  resource_kind: 'storage',
                                  is_aggregated: false # billed per hour/month, per GB
storage_resource = plan.billing_resources.create! product: storage_product
storage_resource.prices.create! price: 0.0001369863,
                                currency: 'USD',
                                billing_phase: storage_resource.billing_phases.first,
                                regions: Region.all
# Local Disk
local_disk_product = Product.create!(
  name: 'local_disk',
  label: 'Temporary Disk',
  kind: 'resource',
  unit: 1,
  unit_type: 'GB',
  resource_kind: 'local_disk',
  is_aggregated: false
)
local_disk_resource = plan.billing_resources.create! product: local_disk_product
local_disk_resource.prices.create! price: 0.0001369863,
                                   currency: 'USD',
                                   billing_phase: local_disk_resource.billing_phases.first,
                                   regions: Region.all

# Bandwidth Product
bandwidth_product = Product.create!(
  name: 'bandwidth',
  label: 'Bandwidth',
  kind: 'resource',
  unit: 1,
  unit_type: 'GB',
  resource_kind: 'bandwidth',
  is_aggregated: true # Once you used it, you pay for it.
)
bandwidth_resource = plan.billing_resources.create!(product: bandwidth_product)
bandwidth_resource.prices.create!(price: 0, max_qty: 1024, currency: 'USD', billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # First 1TB is free
bandwidth_resource.prices.create!(price: 0.09, max_qty: 10240, currency: 'USD', billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # 1TB - 10TB
bandwidth_resource.prices.create!(price: 0.07, max_qty: nil, currency: 'USD', billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # 10TB+

# Backup Product
backup_product = Product.create!(
  name: 'backup',
  label: 'Backup & Template Storage',
  kind: 'resource',
  unit: 1,
  unit_type: 'GB',
  resource_kind: 'backup',
  is_aggregated: false
)
backup_resource = plan.billing_resources.create!(product: backup_product)
backup_resource.prices.create!(price: 0.0000684932, currency: 'USD', billing_phase: backup_resource.billing_phases.first, regions: Region.all)

BillingResourcePrice.all.each do |i|
  i.regions << Region.first
end

UserGroup.all.each do |g|
  g.update billing_plan: plan
end

puts "Setting up settings & features..."
Setting.setup!
Feature.setup!
Feature.find_by(name: 'updated_cr_cert').update active: true

puts "Setting default settings to dev environment..."
Setting.find_by(name: 'hostname').update value: 'controller.cstacks.local:3005'
Setting.find_by(name: 'cr_le').update value: 'controller.cstacks.local'
Setting.find_by(name: 'registry_base_url').update value: 'registry.cstacks.local'
Setting.find_by(name: 'registry_node').update value: '127.0.0.1'
Setting.find_by(name: 'registry_ssh_port').update value: '22'
Setting.find_by(name: 'le_validation_server').update value: '127.0.0.1:3005'

puts "Creating log & metric clients..."
mc = MetricClient.create! endpoint: 'http://127.0.0.1:9090'
lc = LogClient.create! endpoint: 'http://127.0.0.1:3100'
region.update metric_client: mc, log_client: lc, loki_endpoint: 'http://127.0.0.1:3100'

puts "Creating dev node..."
region.nodes.create! label: 'csdev',
                     hostname: 'csdev',
                     primary_ip: vagrant_vm_ip.gsub("\n",""),
                     public_ip: '127.0.0.1',
                     active: true,
                     ssh_port: 22,
                     block_write_bps: 0,
                     block_read_bps: 0,
                     block_write_iops: 0,
                     block_read_iops: 0

puts "Creating network..."
network = Network.create! cidr: "10.167.186.0/24",
                          is_public: false,
                          is_ipv4: true,
                          active: true,
                          name: "dev",
                          label: "Dev Network"
network.regions << region

puts "Configuring DNS..."
pdns_api_key = File.exist?("/home/vagrant/.pdns/api_key") ? File.read("/home/vagrant/.pdns/api_key").gsub("\n","") : ""
pdns_web_key = File.exist?("/home/vagrant/.pdns/web_auth_pass") ? File.read("/home/vagrant/.pdns/web_auth_pass").gsub("\n","") : ""

pdns_driver = ProvisionDriver.create!(
  endpoint: 'http://localhost:8081/api/v1/servers',
  settings: {
    config: {
      zone_type: 'Native',
      masters: [], # When zone_type == 'Master', add the primary NS server here.
      nameservers: ['ns1.cstacks.local.'],
      server: 'localhost'
    }
  },
  module_name: 'Pdns',
  username: 'admin',
  api_key: Secret.encrypt!(pdns_web_key), # WebServer PW
  api_secret: Secret.encrypt!(pdns_api_key) # API-Key
)

dns_type = ProductModule.create!(name: 'dns', primary: pdns_driver)
pdns_driver.product_modules << dns_type
Dns::Zone.create! name: 'cstacks.local',
                  provider_ref: 'cstacks.local.',
                  provision_driver: pdns_driver

puts "Creating load balancer..."
LoadBalancer.create! label: 'dev',
                     region: region,
                     domain: 'a.cstacks.local',
                     ext_ip: [ '127.0.0.1' ],
                     internal_ip: [ '127.0.0.1', vagrant_vm_ip.gsub("\n","") ],
                     public_ip: '127.0.0.1',
                     direct_connect: true,
                     cert_encrypted: Secret.encrypt!(File.read("/home/vagrant/.ssl_wildcard/sharedcert.pem"))

puts "Creating default admin user..."
group = UserGroup.create! name: 'default',
                          is_default: true,
                          billing_plan: plan
group.regions << region
user = User.new fname: 'Default',
                lname: 'User',
                email: 'admin@cstacks.local',
                bypass_billing: true,
                currency: 'USD',
                is_admin: true,
                password: 'changeme!',
                password_confirmation: 'changeme!',
                user_group: group
user.skip_confirmation!
user.save

