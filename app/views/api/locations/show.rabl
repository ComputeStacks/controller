object @location
attributes :id, :name
child :regions, object_root: false do
  attribute :id, :name
end