##
# Each check prints the address it dialed. That matters because a node's transports no
# longer all share one address: SSH and Docker use primary_ip, while the cs-agent uses
# Node#agent_address (primary_ip unless agent_host overrides it).
def report_agent_connectivity(node)
  probe = Agent::Client.for_node(node).probe
  where = node.agent_host.present? ? "#{probe[:url]} via agent_host" : probe[:url]
  status = probe[:status] ? "HTTP #{probe[:status]}" : "no response"
  prefix = probe[:ok] ? "cs-agent" : "[FAILED] cs-agent"
  puts "#{prefix}: #{node.label} (#{where}) - #{status} - #{probe[:detail]}"
  probe[:ok]
end

namespace :test_connection do
  desc "Check connectivity to every node (SSH, Docker, cs-agent) and to the DNS provider"
  task all: :environment do
    Rake::Task["test_connection:nodes"].execute
    Rake::Task["test_connection:dns"].execute
  end

  desc "Check every node's SSH, Docker and cs-agent connectivity"
  task nodes: :environment do
    docker_client_opts = Docker.connection.options
    docker_client_opts[:connect_timeout] = 3
    docker_client_opts[:read_timeout] = 3
    docker_client_opts[:write_timeout] = 3
    Node.all.each do |node|
      begin
        puts "Node SSH: #{node.label} (#{node.primary_ip}:#{node.ssh_port}) - #{node.host_client.client.exec!("date")}"
      rescue
        puts "[FAILED] Node SSH: #{node.label} (#{node.primary_ip}:#{node.ssh_port})"
      end

      begin
        mod_client = Docker::Connection.new("tcp://#{node.primary_ip}:2376", docker_client_opts)
        result = Docker.ping(mod_client)
        puts "Docker ping: #{node.label} (#{node.primary_ip}:2376) - #{result}"
      rescue
        puts "[FAILED] Docker ping: #{node.label} (#{node.primary_ip}:2376)"
      end

      report_agent_connectivity node
    end
  end

  ##
  # Just the agent leg. Run this before and after setting a node's Agent Host — it is the
  # supported form of the manual `curl http://<address>:8500/v1/admin/changelog` check, and
  # it reports nothing to the event log, so it is safe to run repeatedly during a cutover.
  desc "Check only the cs-agent leg for every node (safe to re-run during an Agent Host cutover)"
  task agent: :environment do
    nodes = Node.all
    if nodes.empty?
      puts "No nodes configured."
      next
    end
    failed = nodes.reject { |node| report_agent_connectivity node }
    puts failed.empty? ? "All #{nodes.count} node(s) reachable." : "#{failed.count} of #{nodes.count} node(s) FAILED: #{failed.map(&:label).join(", ")}"
  end

  desc "Check connectivity to the configured DNS provider"
  task dns: :environment do
    provision_driver = ProvisionDriver.first
    if provision_driver.nil?
      puts "DNS Not Configured, Skipping..."
    elsif provision_driver.module_name == "Pdns"
      v = provision_driver.service_client.exec!("get", Pdns.config[:server])["version"]
      puts "Found PowerDNS Version: #{v}"
    elsif provision_driver.module_name == "AutoDNS"
      client = provision_driver.service_client
      unless client.auth.is_a?(AutoDNS::Auth)
        puts "Missing AutoDNS conf"
        return
      end
      primary_ns = provision_driver.settings.dig("config", "master_ns")
      find_zone_data = %(<task><code>0205</code><zone><name>mytestdomain.net</name><system_ns>#{primary_ns}</system_ns></zone></task>)
      auth = %(<auth><user>#{provision_driver.username}</user><password>#{Secret.decrypt!(provision_driver.api_key)}</password><context>#{Secret.decrypt!(provision_driver.api_secret)}</context></auth>)
      data = '<?xml version="1.0" encoding="UTF-8"?><request>' + auth + find_zone_data + "</request>"

      response = HTTP.timeout(40).headers(accept: "application/xml", content_type: "application/xml").post provision_driver.endpoint, body: data

      response.status.success? ? "Successful connection to AutoDNS" : "AutoDNS Error: #{response.body}"
    else
      puts "Unknown driver: #{provision_driver.module_name}"
    end
  end
end
