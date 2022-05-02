namespace :test_connection do

  task all: :environment do
    Rake::Task['test_connection:nodes'].execute
    Rake::Task['test_connection:consul'].execute
    Rake::Task['test_connection:dns'].execute
  end

  task nodes: :environment do
    docker_client_opts = Docker.connection.options
    docker_client_opts[:connect_timeout] = 3
    docker_client_opts[:read_timeout] = 3
    docker_client_opts[:write_timeout] = 3
    Node.all.each do |node|
      begin
        puts "Node SSH: #{node.label} - #{node.host_client.client.exec!("date")}"
      rescue
        puts "[FAILED] Node SSH: #{node.label}"
      end

      begin
        mod_client = Docker::Connection.new("tcp://#{node.primary_ip}:2376", docker_client_opts)
        result = Docker.ping(mod_client)
        puts "Docker ping: #{node.label} - #{result}"
      rescue
        puts "[FAILED] Docker ping: #{node.label}"
      end
    end
  end

  task consul: :environment do
    docker_client_opts = Docker.connection.options
    docker_client_opts[:connect_timeout] = 3
    docker_client_opts[:read_timeout] = 3
    docker_client_opts[:write_timeout] = 3
    Region.all.each do |region|
      dc = region.name.strip.downcase
      n = region.nodes.online.first&.primary_ip
      if n.blank?
        puts "[FAILED] Consul Region: #{dc} has no online nodes."
        next
      end
      begin
        peers = Diplomat::Status.peers({ http_addr: "https://#{n}:8501", dc: dc })
        puts %Q[Consul Region: #{dc} #{n} - #{peers.is_a?(Array) ? "found #{peers.count} nodes": peers}]
      rescue
        puts "[FAILED] Consul Region: #{dc} Failed to connect to node: #{n}"
      end
    end
  end

  task dns: :environment do
    provision_driver = ProvisionDriver.first
    if provision_driver.nil?
      puts "DNS Not Configured, Skipping..."
    elsif provision_driver.module_name == 'Pdns'
      v = provision_driver.service_client.exec!('get', Pdns.config[:server])['version']
      puts "Found PowerDNS Version: #{v}"
    elsif provision_driver.module_name == 'AutoDNS'
      client = provision_driver.service_client
      unless client.auth.is_a?(AutoDNS::Auth)
        puts "Missing AutoDNS conf"
        return
      end
      primary_ns = provision_driver.settings.dig('config', 'master_ns')
      find_zone_data = %Q[<task><code>0205</code><zone><name>mytestdomain.net</name><system_ns>#{primary_ns}</system_ns></zone></task>]
      auth = %Q[<auth><user>#{provision_driver.username}</user><password>#{Secret.decrypt!(provision_driver.api_key)}</password><context>#{Secret.decrypt!(provision_driver.api_secret)}</context></auth>]
      data = '<?xml version="1.0" encoding="UTF-8"?><request>' + auth + find_zone_data + '</request>'

      response = HTTP.timeout(40).headers(accept: "application/xml", content_type: "application/xml").post provision_driver.endpoint, body: data

      response.status.success? ? "Successful connection to AutoDNS" : "AutoDNS Error: #{response.body.to_s}"
    else
      puts "Unknown driver: #{provision_driver.module_name}"
    end
  end

end
