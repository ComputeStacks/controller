attributes :id,
           :label,
           :active,
           :sort,
           :created_at,
           :updated_at

child :container_images do
  extends 'api/container_images/container_image'
end
