collection @collaborators, root: 'collaborators', object_root: false
attributes :id, :created_at, :updated_at
node :collaborator do |i|
  {
    id: i.collaborator&.id,
    email: i.collaborator&.email,
    full_name: i.collaborator&.full_name
  }
end
