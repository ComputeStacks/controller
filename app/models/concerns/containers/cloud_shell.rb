module Containers::CloudShell
  extend ActiveSupport::Concern

  def cloud_shell_errors
    errors = []
    errors << "Missing SSH Port" if public_port.zero?
    errors << "Password Authentication is disabled" unless pw_auth
    errors << "Missing IP Address" if ip_addr.blank?
    errors
  end

  def cloud_shell_token
    return nil unless region.guac_available?
    return nil if public_port.zero?
    return nil unless pw_auth
    return nil if ip_addr.blank?

    key_hex = region.guac_key
    key = [key_hex].pack("H*")
    iv = ["00000000000000000000000000000000"].pack("H*")

    sftp_root_path = "/home/sftpuser"

    # For WordPress sites, we can pre-configure the sftp client.
    if deployment.services.where(container_image: {role: "wordpress"}).joins(:container_image).count == 1
      wp_service = deployment.services.where(container_image: {role: "wordpress"}).joins(:container_image).first
      sftp_root_path = "/home/sftpuser/apps/#{wp_service.name}/wordpress"
    end

    data = {
      "username" => "",
      "expires" => "#{1.minute.from_now.to_i}000",
      "connections" => {
        "container-name" => {
          "protocol" => "ssh",
          "parameters" => {
            "hostname" => ip_addr,
            "port" => public_port,
            "username" => "sftpuser",
            "password" => password,
            "enable-sftp" => "true",
            "sftp-root-directory" => sftp_root_path,
            "server-alive-interval" => "30",
            "command" => "cd #{sftp_root_path} && cat /etc/motd && /bin/bash"
          }
        }
      }
    }

    data = Oj.dump data
    sig = OpenSSL::HMAC.digest("sha256", key, data)

    # Encryption
    # hmac_key = OpenSSL::KDF.pbkdf2_hmac key, salt: "", iterations: 10, length: 16, hash: digest
    cipher = OpenSSL::Cipher.new("AES-128-CBC")
    cipher.encrypt
    cipher.iv = iv
    cipher.key = key

    encrypted = cipher.update "#{sig}#{data}"
    encrypted << cipher.final

    response = HTTP.post("#{region.guac_url}/api/tokens", form: {
      data: Base64.encode64(encrypted).delete("\n")
    })

    if response.status.success?
      result = Oj.load response.body.to_s
      result["authToken"]
    else
      SystemEvent.create!(
        message: "Guacamole Error: #{id}",
        log_level: "warn",
        data: {
          "sftp_container" => id,
          "errors" => response.body.to_s

        }
      )
      nil
    end
  end
end
