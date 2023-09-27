vagrant_vm_ip = if RUBY_PLATFORM =~ /linux/ # Anything else and we're running local, so just use 127.0.0.1
                  `ip -j addr show dev eth0 | jq -r '.[0].addr_info | map(select(.family == "inet"))[0].local'`
                else
                  '127.0.0.1'
                end
lb_cert_path = if `whoami`.strip == 'vagrant'
                 '/home/vagrant/.ssl_wildcard/sharedcert.pem'
               else
                 "#{Rails.root.to_s}/lib/dev/test_wildcard_ssl/sharedcert-test-crt"
               end
puts "Creating default location and region..."
location = Location.create! name: "dev"

consul_token = File.exist?("/home/vagrant/consul.token") ? File.read("/home/vagrant/consul.token").gsub("\n","") : ""

region = location.regions.create! name: "dev", pid_limit: 150, ulimit_nofile_soft: 1024, ulimit_nofile_hard: 1024, consul_token: consul_token, network_driver: 'bridge'

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
Rake::Task['load_containers'].execute

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

puts "Setting default settings to dev environment..."
Setting.find_by(name: 'hostname').update value: 'controller.cstacks.local:3005'
Setting.find_by(name: 'cr_le').update value: 'controller.cstacks.local'
Setting.find_by(name: 'registry_base_url').update value: 'registry.cstacks.local'
Setting.find_by(name: 'registry_node').update value: '127.0.0.1'
Setting.find_by(name: 'registry_ssh_port').update value: '22'
Setting.find_by(name: 'le_validation_server').update value: '127.0.0.1:3005'
Setting.find_by(name: 'cs_bastion_image').update value: 'ghcr.io/computestacks/cs-docker-bastion:latest'

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
network = Network.create! subnet: "10.167.0.0/21",
                          is_public: true,
                          is_ipv4: true,
                          active: true,
                          name: "dev",
                          label: "Dev Network",
                          network_driver: 'bridge',
                          region: region
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
                     cert_encrypted: Secret.encrypt!(File.read(lb_cert_path)),
                     skip_validation: true

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


