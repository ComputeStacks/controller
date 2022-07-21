object false

node :volumes do
  @volumes.map do |i|
    partial "api/admin/volumes/vol", object: i
  end
end
