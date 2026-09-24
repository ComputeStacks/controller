module Dns
  def self.table_name_prefix
    "dns_"
  end

  # Validate Hostname
  def self.valid_hostname?(hostname)
    /^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*$/.match?(hostname) ? true : false
  end

  # Validate domain
  def self.valid_domain?(domain)
    /^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,6}$/.match?(domain) ? true : false
  end
end
