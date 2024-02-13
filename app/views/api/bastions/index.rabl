collection @bastions, root: 'bastions', object_root: false
attributes :id, :name, :status, :node_id, :ip_addr, :created_at, :updated_at
node :port, &:public_port
node :username do
  'sftpuser'
end
node :password, &:password
node :on_latest_image, &:latest_image?
