
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
ContainerImageProvider.create!(
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

puts "Setting up billing products..."
plan = BillingPlan.create! name: 'default', is_default: true

# Container Package: Small
puts "..small container product"
Product.create! label: 'Small', kind: 'package'

# Storage Product
Product.create! label: 'Storage',
                kind: 'resource',
                unit: 1,
                unit_type: 'GB',
                resource_kind: 'storage',
                is_aggregated: false # billed per hour/month, per GB

# Local Disk
puts "...local disk product"
Product.create!(
  label: 'Temporary Disk',
  kind: 'resource',
  unit: 1,
  unit_type: 'GB',
  resource_kind: 'local_disk',
  is_aggregated: false
)

# Bandwidth Product
puts "...local bandwidth product"
Product.create!(
  label: 'Bandwidth',
  kind: 'resource',
  unit: 1,
  unit_type: 'GB',
  resource_kind: 'bandwidth',
  is_aggregated: true # Once you used it, you pay for it.
)

# Backup Product
puts "...local backup product"
Product.create!(
  label: 'Backup & Template Storage',
  kind: 'resource',
  unit: 1,
  unit_type: 'GB',
  resource_kind: 'backup',
  is_aggregated: false
)

puts "Setting up settings & features..."
Setting.setup!
Feature.setup!

puts "Creating default admin user..."
group = UserGroup.create! name: 'default',
                          is_default: true,
                          billing_plan: plan

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


puts "Creating Container Images..."
Rake::Task['load_containers'].execute
