attributes :id,
           :container_image_id,
           :name,
           :label,
           :param_type,
           :created_at,
           :updated_at

node :env_value do |i|
  i.param_type == 'static' ? nil : i.value
end
node :static_value do |i|
  i.param_type == 'static' ? i.value : nil
end