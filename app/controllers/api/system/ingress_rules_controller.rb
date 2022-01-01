class Api::System::IngressRulesController < Api::System::BaseController

  def index
    remote_ip = request.remote_ip.gsub("::ffff:","")
    if Rails.env.development?
      node = Node.first
    else
      node = Node.find_by("public_ip = ? OR primary_ip = ? OR hostname = ?", remote_ip, remote_ip, remote_ip)
      return api_obj_missing if node.nil?
    end

    data = { rules: [] }
    node.iptable_rules.each do |i|
      if i.sftp_container # should never hit this...
        data[:rules] << {
          proto: i.proto,
          nat: i.port_nat,
          port: i.port,
          dest: i.sftp_container.local_ip
        }
      elsif i.container_service
        i.container_service.containers.each do |contianer|
          data[:rules] << {
            proto: i.proto,
            nat: i.port_nat,
            port: i.port,
            dest: contianer.local_ip
          }
        end
      end
    end
    render json: data.to_json
  end

end
