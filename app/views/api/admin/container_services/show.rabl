object @container_service
extends "api/container_services/service"
attribute :override_autoremove
child deployment: :project do
  attributes :id, :name
end
child :user do
  extends 'api/admin/users/short'
end
