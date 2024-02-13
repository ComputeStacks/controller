module ConsulTestContainerConcern

  def before_setup
    super
    Volume.all.each do |i|
      i.update_attribute :usage, i.id
      i.update_consul!
      backup_data = {
        'name' => i.name,
        'usage' => i.id * 1024, # predictable, but fake, data
        'size' => i.id * 4096,
        'archives' => []
      }
      Diplomat::Kv.put("borg/repository/#{i.name}", backup_data.to_json, { http_addr: "#{CONSUL_API_PROTO}://#{ENV['VAGRANT_VM_IP']}:#{CONSUL_API_PORT}" })
    end
  end

  def after_teardown
    Volume.all.each do |i|
      Diplomat::Kv.delete "borg/repository/#{i.name}", { http_addr: "#{CONSUL_API_PROTO}://#{ENV['VAGRANT_VM_IP']}:#{CONSUL_API_PORT}" }
    end
    super
  end

end
