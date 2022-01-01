collection @volumes
attributes :id, :label, :created_at, :updated_at
child :user do
  extends 'api/admin/users/short'
end
