collection @container_services, object_root: false, root: 'container_services'
if params[:all]
  extends 'api/admin/container_services/show'
  attribute :override_autoremove
else
  attributes :id, :name, :label, :override_autoremove, :created_at, :updated_at
  child deployment: :project do
    attributes :id, :name
  end
  child :user do
    extends 'api/admin/users/short'
  end
end
