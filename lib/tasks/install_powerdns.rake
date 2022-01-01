task install_powerdns: :environment do

  dns_type = ProductModule.find_by(name: 'dns')
  dns_type = ProductModule.create!(name: 'dns') if dns_type.nil?

  pdns_driver = ProvisionDriver.create!(
      endpoint: 'http://ns1.computestacks.net:8081/api/v1/servers',
      settings: {
          config: {
              zone_type: 'Master',
              masters: ['ns1.computestacks.net.'],
              nameservers: %w(ns1.computestacks.net. ns2.computestacks.net.),
              server: 'localhost'
          }
      },
      module_name: 'Pdns',
      username: 'admin',
      api_key: Secret.encrypt!('EfC6H9c2Bdnafx1u'), # WebServer PW
      api_secret: Secret.encrypt!('ld94r36MTqRI9OOa') # API-Key
  )
  pdns_driver.product_modules << dns_type

end
