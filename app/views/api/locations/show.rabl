object @location
attributes :id, :name
child :regions, object_root: false do
  attribute :id, :name
  node :node_status do |i|
    Nodes::CustomerStatusPresenter.for_region(i)
  end
end
