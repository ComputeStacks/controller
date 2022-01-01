# client = Pdns::Client.new('http://138.68.59.217:8081/api/v1/servers/localhost', Pdns::Auth.new(0,'admin', 'RSpjIXrSpWZY5xqB', 'ZcymC04eywzvUJqA'))
# zone = Pdns::Dns::Zone.new(client, 'example.com')
task install: :environment do

  puts "Configuring App..."

  location = Location.first
  location = Location.create!(name: 'demo') if location.nil?
  Region.create!(name: "DM01", location: location) if Region.first.nil?
  Rake::Task['load_products'].execute
  Rake::Task['default_settings'].execute
  Rake::Task['load_containers'].execute

end
