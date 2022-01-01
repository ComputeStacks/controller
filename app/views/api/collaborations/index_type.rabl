collection @collaborators, root: 'collaborators', object_root: false
attributes :id
node :resource_owner do |i|
  {
    id: i.resource_owner&.id,
    email: i.resource_owner&.email,
    full_name: i.resource_owner&.full_name
  }
end
