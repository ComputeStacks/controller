task setup_dev: :environment do

  vagrant_vm_ip = if ENV['USER'] == 'vagrant' # Anything else and we're running local, so just use 127.0.0.1
                    `ip -j addr show dev ens18 | jq -r '.[0].addr_info | map(select(.family == "inet"))[0].local'`
                  else
                    ENV['VAGRANT_VM_IP'].blank? ? '127.0.0.1' : ENV['VAGRANT_VM_IP']
                  end
  vagrant_vm_ip = vagrant_vm_ip.strip

  puts "Creating default location and region..."
  location = Location.where(name: 'dev').exists? ? Location.find_by(name: 'dev') : Location.create!(name: "dev")

  ssh_client = DockerSSH::Node.new("ssh://#{vagrant_vm_ip}:22", {key: "#{Rails.root}/#{ENV['CS_SSH_KEY']}"})

  consul_token = if ENV['USER'] == 'vagrant'
                   File.exist?("/home/vagrant/consul.token") ? File.read("/home/vagrant/consul.token").gsub("\n","") : ""
                 elsif vagrant_vm_ip != '127.0.0.1'
                   ssh_client.client.exec!("if [[ -f /home/vagrant/consul.token ]]; then cat /home/vagrant/consul.token; else echo ''; fi").strip
                 else
                   ''
                 end

  if consul_token.blank?
    puts "Error, unable to read consul token. Check connection settings."
    return
  end

  consul_token_path = ENV['CONSUL_TOKEN_PATH'].strip

  if consul_token_path != "/home/vagrant/consul.token" && !consul_token_path.blank?
    File.write("#{Rails.root}/#{consul_token_path}", consul_token)
  end

  lb_cert = if ENV['USER'] == 'vagrant'
              File.read('/home/vagrant/.ssl_Wildcard/sharedcert.pem')
            elsif vagrant_vm_ip != '127.0.0.1'
              ssh_client.client.exec!("if [[ -f /home/vagrant/.ssl_wildcard/sharedcert.pem ]]; then cat /home/vagrant/.ssl_wildcard/sharedcert.pem; else echo ''; fi").strip
            else
              File.read("#{Rails.root}/lib/dev/test_wildcard_ssl/sharedcert-test-crt")
            end

  if lb_cert.blank?
    puts "Error, unable to load wildcard certificate file"
    return
  end

  region = if location.regions.empty?
             location.regions.create!(
               name: "dev",
               pid_limit: 150,
               ulimit_nofile_soft: 1024,
               ulimit_nofile_hard: 1024,
               consul_token: consul_token,
               network_driver: 'bridge'
             )
           else
             location.regions.first
           end

  if LoadBalancer.all.empty?
    LoadBalancer.create! label: 'dev',
                         region: region,
                         domain: 'a.cstacks.local',
                         ext_ip: [ '127.0.0.1' ],
                         internal_ip: [ '127.0.0.1', vagrant_vm_ip ],
                         public_ip: '127.0.0.1',
                         direct_connect: true,
                         cert_encrypted: Secret.encrypt!(lb_cert),
                         skip_validation: true
  end


  # put default group into region
  group = UserGroup.find_by name: 'default', is_default: true
  group.regions << region unless group.regions.include?(region)
  # Default Prices
  plan = BillingPlan.find_by is_default: true

  container_product = Product.find_by name: 'small', kind: 'package'
  if container_product.package.nil?
    container_product.create_package cpu: 1, memory: 512, storage: 10, local_disk: 5, bandwidth: 500
    container_product_resource = plan.billing_resources.create! product: container_product
    container_product_resource.prices.create! price: 0.00343,
                                              currency: 'USD',
                                              billing_phase: container_product_resource.billing_phases.first,
                                              regions: Region.all
  end

  storage_product = Product.find_by name: 'storage', kind: 'resource'
  if storage_product.billing_resources.empty?
    storage_resource = plan.billing_resources.create! product: storage_product
    storage_resource.prices.create! price: 0.0001369863,
                                    currency: 'USD',
                                    billing_phase: storage_resource.billing_phases.first,
                                    regions: Region.all
  end

  local_disk_product = Product.find_by name: 'temporary-disk', kind: 'resource'
  if local_disk_product.billing_resources.empty?
    local_disk_resource = plan.billing_resources.create! product: local_disk_product
    local_disk_resource.prices.create! price: 0.0001369863,
                                       currency: 'USD',
                                       billing_phase: local_disk_resource.billing_phases.first,
                                       regions: Region.all
  end

  bandwidth_product = Product.find_by name: 'bandwidth', kind: 'resource'
  if bandwidth_product.billing_resources.empty?
    bandwidth_resource = plan.billing_resources.create!(product: bandwidth_product)
    bandwidth_resource.prices.create!(price: 0, max_qty: 1024, currency: 'USD', billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # First 1TB is free
    bandwidth_resource.prices.create!(price: 0.09, max_qty: 10240, currency: 'USD', billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # 1TB - 10TB
    bandwidth_resource.prices.create!(price: 0.07, max_qty: nil, currency: 'USD', billing_phase: bandwidth_resource.billing_phases.first, regions: Region.all) # 10TB+
  end

  backup_product = Product.find_by resource_kind: 'backup', kind: 'resource'
  if backup_product.billing_resources.empty?
    backup_resource = plan.billing_resources.create!(product: backup_product)
    backup_resource.prices.create!(price: 0.0000684932, currency: 'USD', billing_phase: backup_resource.billing_phases.first, regions: Region.all)
  end
  BillingResourcePrice.all.each do |i|
    i.regions << region unless i.regions.include?(region)
  end

  UserGroup.all.each do |g|
    g.update(billing_plan: plan) if g.billing_plan.nil?
  end

  puts "Setting default settings to dev environment..."
  Setting.find_by(name: 'hostname').update value: 'controller.cstacks.local:3005'
  Setting.find_by(name: 'cr_le').update value: 'controller.cstacks.local'
  Setting.find_by(name: 'registry_base_url').update value: 'registry.cstacks.local'
  Setting.find_by(name: 'registry_node').update value: vagrant_vm_ip
  Setting.find_by(name: 'registry_ssh_port').update value: '22'
  Setting.find_by(name: 'le_validation_server').update value: '192.168.121.1:3005'
  Setting.find_by(name: 'cs_bastion_image').update value: 'ghcr.io/computestacks/cs-docker-bastion:latest'

  puts "Creating log & metric clients..."
  mc = MetricClient.first.nil? ? MetricClient.create!(endpoint: "http://#{vagrant_vm_ip}:9090") : MetricClient.first
  lc = LogClient.first.nil? ? LogClient.create!(endpoint: "http://#{vagrant_vm_ip}:3100") : LogClient.first
  region.update metric_client: mc, log_client: lc, loki_endpoint: "http://#{vagrant_vm_ip}:3100"

  if region.nodes.empty?
    puts "Creating dev node..."
    region.nodes.create! label: 'csdev',
                         hostname: 'csdev',
                         primary_ip: vagrant_vm_ip,
                         public_ip: vagrant_vm_ip,
                         active: true,
                         ssh_port: 22,
                         block_write_bps: 0,
                         block_read_bps: 0,
                         block_write_iops: 0,
                         block_read_iops: 0
  end

  unless Network.where(name: 'dev', network_driver: 'bridge').exists?
    puts "Creating network..."
    Network.create! subnet: "10.167.0.0/21",
                    active: true,
                    name: "dev",
                    label: "Dev Network",
                    network_driver: 'bridge',
                    region: region
  end


  # PowerDNS Setup
  if ProvisionDriver.all.empty?
    pdns_driver = ProvisionDriver.create!(
      endpoint: "http://localhost:#{ENV['PDNS_API_PORT']}/api/v1/servers",
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
      api_key: Secret.encrypt!('d3vE_nv1rnm3n1'), # WebServer PW
      api_secret: Secret.encrypt!('d3vE_nv1rnm3n1') # API-Key
    )

    dns_type = ProductModule.create!(name: 'dns', primary: pdns_driver)
    pdns_driver.product_modules << dns_type
    Dns::Zone.create! name: 'cstacks.local',
                      provider_ref: 'cstacks.local.',
                      provision_driver: pdns_driver
  end



end
