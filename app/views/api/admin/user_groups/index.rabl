object false

node :user_groups do
  @groups.map do |i|
    partial "api/admin/user_groups/group", object: i
  end
end

