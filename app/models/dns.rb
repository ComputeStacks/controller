module Dns
  def self.table_name_prefix
    'dns_'
  end

  # Validate Hostname
  def self.valid_hostname?(hostname)
    hostname.match(/^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*$/) ? true : false
  end

  # Validate domain
  def self.valid_domain?(domain)
    domain.match(/^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,6}$/) ? true : false
  end
end
