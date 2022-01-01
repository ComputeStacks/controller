object @alert
attributes :id, :name, :status, :severity, :description, :value, :labels, :public_url

child :container do
  attributes :id, :name
end

child :sftp_container do
  attributes :id, :name
end
