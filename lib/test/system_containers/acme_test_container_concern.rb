module AcmeTestContainerConcern

  def before_setup
    super
    redirect_output = RUBY_PLATFORM =~ /linux/ ? '>/dev/null 2>/dev/null' : '&>/dev/null'

    unless system("docker info #{redirect_output}")
      raise "Error! Ensure docker is running!"
    end

    return true if system("docker inspect acme-test #{redirect_output}") # Already running!
    `docker run -d --name acme-test --rm -e GODEBUG="tls13=1" -e PEBBLE_VA_ALWAYS_VALID=1 -p 14000:14000 -p 15000:15000 letsencrypt/pebble:latest pebble -config /test/config/pebble-config.json -strict`
    sleep(5)
  end

end
