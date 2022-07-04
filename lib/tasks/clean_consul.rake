task clean_consul: :environment do

  if Rails.env.production?
    raise "Task not available in production environment."
  end

  Region.all.each do |region|
    node = region.nodes.online.first
    if node.nil?
      puts "Skipping #{region.name}, no online nodes found."
      next
    end
    consul_config = { http_addr: "http://#{node.primary_ip}:8500", dc: region.name.strip.downcase, token: region.consul_token }

    puts "Cleaning volumes..."
    begin
      Diplomat::Kv.get_all("volumes/", consul_config).each do |i|
        Diplomat::Kv.delete i[:key], consul_config
      end
    rescue Diplomat::KeyNotFound
      puts "...no volumes found."
    end

    puts "Cleaning jobs..."
    begin
      Diplomat::Kv.get_all("jobs/", consul_config).each do |i|
        Diplomat::Kv.delete i[:key], consul_config
      end
    rescue Diplomat::KeyNotFound
      puts "...no jobs found."
    end

    puts "Cleaning borg..."
    begin
      Diplomat::Kv.get_all("borg/", consul_config).each do |i|
        Diplomat::Kv.delete i[:key], consul_config
      end
    rescue Diplomat::KeyNotFound
      puts "...no borg archives found."
    end

    puts "Cleaning nodes..."
    begin
      Diplomat::Kv.get_all("nodes/", consul_config).each do |i|
        Diplomat::Kv.delete i[:key], consul_config
      end
    rescue Diplomat::KeyNotFound
      puts "...no nodes found."
    end

    puts "Cleaning projects..."
    begin
      Diplomat::Kv.get_all("projects/", consul_config).each do |i|
        Diplomat::Kv.delete i[:key], consul_config
      end
    rescue Diplomat::KeyNotFound
      puts "...no projects found."
    end

  end


end
