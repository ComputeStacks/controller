# Ensure our test PowerDNS container is running
module PdnsTestContainerConcern

  def before_setup
    super
    docker_cmd = RUBY_PLATFORM =~ /linux/ ? 'sudo docker' : 'docker'
    redirect_output = RUBY_PLATFORM =~ /linux/ ? '>/dev/null 2>/dev/null' : '&>/dev/null'
    unless system("#{docker_cmd} info #{redirect_output}")
      raise "Error! Ensure docker is running!"
    end
    return true if system("#{docker_cmd} inspect pdns-caa #{redirect_output}") # Already running!
    `#{docker_cmd} run --rm -d --name pdns-caa -v ${PWD}/lib/dev/power_dns/caa-tester/sqlite-db:/etc/pdns/sqlite-db -v ${PWD}/lib/dev/power_dns/caa-tester/pdns.conf:/etc/pdns/pdns.conf -p 25353:53/udp tcely/powerdns-server --daemon=no --guardian=no --loglevel=9`
    sleep(5)
  end

end
