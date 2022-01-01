object false

node :volumes do
  @volumes.map do |i|
    partial "api/volumes/vol", object: i
  end
end