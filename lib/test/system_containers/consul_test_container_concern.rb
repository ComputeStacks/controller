# Ensure our test containers are running
module ConsulTestContainerConcern

  def before_setup
    super
    boot_consul!

    # Each time we run our tests, all the data is re-seeded by rails,
    # so we need to also update our fake volume data.
    load_fixtures!
  end

  private

  ##
  # Boot consul
  #
  # Will default to the local instance (if it exists), otherwise will attempt to use docker
  # Using the docker cli to avoid issues with port forwarding (since it appears the cli actually handles that)
  #
  def boot_consul!
    redirect_output = RUBY_PLATFORM =~ /linux/ ? '>/dev/null 2>/dev/null' : '&>/dev/null'
    return true if system("which consul && consul members #{redirect_output}") # consul could be running by other means, just quickly check before triggering homebrew
    docker_cmd = RUBY_PLATFORM =~ /linux/ ? 'sudo docker' : 'docker'
    if system("which brew #{redirect_output}") && system("which consul #{redirect_output}")
      system('brew services start consul')
      # unless `brew services list | grep consul | awk '{print $2}'`.split(/\n/)[0] == 'started'
      #   system('brew services start consul')
      # end
    elsif system("which brew #{redirect_output}")
      system('brew install consul && brew services start consul')
      puts "Waiting for consul to boot..."
      sleep(3)
    elsif system("which docker #{redirect_output}")
      return true if system("#{docker_cmd} inspect cs-consul #{redirect_output}") # Already running!
      `#{docker_cmd} run --rm --name=cs-consul -d -p 8500:8500 -e 'CONSUL_LOCAL_CONFIG={"datacenter": "test01", "bootstrap": true, "node_name": "test01"}' consul:latest`
      puts "Waiting for consul to boot"
      sleep(3)
    else
      raise "I dont know how to start consul! please install docker or homebrew"
    end
  end

  def load_fixtures!
    Volume.all.each do |i|
      i.update_attribute :usage, i.id
      i.update_consul!
      # Store backup test data
      backup_data = {
        'name' => i.name,
        'usage' => i.id * 1024, # predictable, but fake, data
        'size' => i.id * 4096,
        'archives' => []
      }
      Diplomat::Kv.put("borg/repository/#{i.name}", backup_data.to_json)

      ##
      # When testing against the live node, we need to push the node details here.
      # node = i.nodes.first
      # dc = node.region.name.strip.downcase
      # ip = node.primary_ip
      # Diplomat::Kv.put("borg/repository/#{i.name}", backup_data.to_json, { http_addr: "https://#{ip}:8501", dc: dc })
    end
  end

end
