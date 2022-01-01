attributes :id, :name, :status, :node_id, :ip_addr, :pw_auth, :created_at, :updated_at
node :port do |i|
  i.public_port
end
node :username do
  'sftpuser'
end
node :password do |i|
  i.password
end
