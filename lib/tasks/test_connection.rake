namespace :test_connection do

  task all: :environment do
    Rake::Task['test_connection:nodes'].execute
    Rake::Task['test_connection:consul'].execute
    Rake::Task['test_connection:autodns'].execute
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
        node_check = Diplomat::Node.get_all({ http_addr: "https://#{n}:8501", dc: dc })
        puts %Q[Consul Region: #{dc} #{n} - #{node_check.is_a?(Array) ? "found #{node_check.count} nodes": node_check}]
      rescue
        puts "[FAILED] Consul Region: #{dc} Failed to connect to node: #{n}"
      end
    end
  end

  task autodns: :environment do
    provision_driver = ProvisionDriver.find_by(module_name: 'AutoDNS')
    if provision_driver.nil?
      puts "AutoDNS Not Configured"
      return
    end
    client = provision_driver.service_client

    find_zone_data = %Q[<task><code>0205</code><zone><name>mytestdomain.net</name><system_ns>ns1.auto-dns.com</system_ns></zone></task>]
    auth = %Q[<auth><user>#{provision_driver.username}</user><password>#{Secret.decrypt!(provision_driver.api_key)}</password><context>#{Secret.decrypt!(provision_driver.api_secret)}</context></auth>]
    data = '<?xml version="1.0" encoding="UTF-8"?><request>' + auth + find_zone_data + '</request>'
    rsp_headers = { 'Content-Type' => 'application/xml', 'Accept' => 'application/xml' }
    opts = { timeout: 40, headers: rsp_headers, body: data }

    puts HTTParty.post(provision_driver.endpoint, opts)
  end

end
