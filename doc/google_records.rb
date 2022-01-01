zone = Dns::Zone.find(20)
params = [
  {
    name: '@',
    priority: 1,
    ttl: 86400,
    type: 'MX',
    hostname: 'ASPMX.L.GOOGLE.COM.'
  },
  {
    name: '@',
    priority: 5,
    ttl: 86400,
    type: 'MX',
    hostname: 'ALT1.ASPMX.L.GOOGLE.COM.'
  },
  {
    name: '@',
    priority: 5,
    ttl: 86400,
    type: 'MX',
    hostname: 'ALT2.ASPMX.L.GOOGLE.COM.'
  },
  {
    name: '@',
    priority: 10,
    ttl: 86400,
    type: 'MX',
    hostname: 'ASPMX2.GOOGLEMAIL.COM.'
  },
  {
    name: '@',
    priority: 10,
    ttl: 86400,
    type: 'MX',
    hostname: 'ASPMX3.GOOGLEMAIL.COM.'
  }
]
params.each do |p|
  record = Dns::ZoneRecord.new(nil, zone)
  response = record.create!(p)
  puts response
end

record = Dns::ZoneRecord.new(nil, zone)
response = record.create!({name: '@', ttl: 86400, type: 'TXT', value: 'v=spf1 include:_spf.google.com ~all'})
