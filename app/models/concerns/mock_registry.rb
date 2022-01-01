module MockRegistry
  extend ActiveSupport::Concern

  def mock_repositories
    data = [
      {
        image: 'myapp',
        tags: [
          {
            tag: 'latest'
          },
          {
            tag: 'v1.0'
          },
          {
            tag: 'beta'
          }
        ]
      },
      {
        image: 'db',
        tags: [
          {
            tag: 'latest'
          }
        ]
      }
    ]
    data.each do |i|
      i[:tags].each do |tag|
        container_check = container_image_provider.container_images.find_by(registry_image_path: i[:image], registry_image_tag: tag[:tag])
        unless container_check.nil?
          tag.merge!({
                     container: {
                       id: container_check.id,
                       name: container_check.name
                     }
                   })
        end
      end
    end
    data
  end

  def mock_deploy!
    set_port! if self.port.zero?
    update_column :status, 'deployed'
  end

end