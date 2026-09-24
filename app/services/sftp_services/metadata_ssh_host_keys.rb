##
# Store Host SSH Keys for a given SFTP Container
module SftpServices
  class MetadataSshHostKeys
    attr_accessor :sftp

    def initialize(sftp)
      self.sftp = sftp
    end

    def perform
      return false if sftp.region.nil?
      # Per-SFTP-container host-keys blob, keyed by the container name (== the
      # container's HOSTNAME, which init_bastion.rb reads). One node per region,
      # so resolving via the region targets the SFTP container's own node.
      Agent::Client.new(sftp.deployment, region: sftp.region).put_managed(sftp.name, data.to_json)
    rescue Agent::Client::NotReady
      false
    end

    private

    def data
      {
        password_auth: sftp.pw_auth,
        host_keys: host_keys,
        motd: ssh_motd
      }
    end

    ##
    # Generate Motd Message
    #
    # Available variables:
    #   * {{ project_name }}
    #   * {{ region }}
    #   * {{ availability_zone }}
    def ssh_motd
      motd_vars = {
        "project_name" => sftp.deployment.name,
        "region" => sftp.location.name,
        "availability_zone" => sftp.region.name
      }
      data = Liquid::Template.parse Setting.ssh_motd
      data.render motd_vars
    rescue => e
      ExceptionAlertService.new(e, "58b5d8d74c9d5786").perform
      ""
    end

    # SSH Host Keys
    def host_keys
      rsa = sftp.ssh_host_keys.find_by(algo: "rsa")
      ed25519 = sftp.ssh_host_keys.find_by(algo: "ed25519")
      keys = {}
      if rsa
        keys[:rsa] = {
          pkey: rsa.pkey,
          pubkey: rsa.pubkey
        }
      end
      if ed25519
        keys[:ed25519] = {
          pkey: ed25519.pkey,
          pubkey: ed25519.pubkey
        }
      end
      keys
    end
  end
end
