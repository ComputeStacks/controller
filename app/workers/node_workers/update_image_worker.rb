module NodeWorkers
  class UpdateImageWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1, queue: 'low'

    def perform(node_id = nil)

      if node_id.blank?
        Node.online.each do |node|
          NodeWorkers::UpdateImageWorker.perform_async node.id
        end
        return
      end

      node = Node.online.find_by(id: node_id)
      return if node.nil?

      ##
      # Pull latest images
      ContainerImage.is_public.each do |image|
        image.image_variants.each do |variant|
          begin
            NodeServices::PullImageService.new(node, variant).perform
          rescue
            next
          end
        end
      end

      ##
      # Update System Images
      images = %W(
        #{Deployment::Sftp.new.image}
        ghcr.io/computestacks/cs-docker-xtrabackup:2.4
        ghcr.io/computestacks/cs-docker-xtrabackup:8.0
        ghcr.io/computestacks/cs-docker-borg:#{Rails.env.production? ? '1.4' : 'latest'}
      )

      images.each do |image|
        i = NodeServices::PullImageService.new node
        i.raw_image = image
        i.perform
      end

      ##
      # Clean stale images
      c = node.client(5)
      return if c.nil?
      result = JSON.parse(c.post("/images/prune?dangling=true", {}))
      if result['ImagesDeleted']
        saved = result['SpaceReclaimed'].zero? ? 0 : result['SpaceReclaimed'] / BYTE_TO_GB
        SystemEvent.create!(
          message: "Pruned #{result['ImagesDeleted'].count} images from node #{node.label}",
          data: {
            'node' => {
              'id' => node.id,
              'label' => node.label
            },
            'removed_images' => result['ImagesDeleted'].count,
            'space_saved' => "#{saved} MB"
          },
          event_code: '75eaa84677838cf7'
        )
      end

    rescue Docker::Error::TimeoutError
      NodeWorkers::UpdateImageWorker.perform_in(10.minutes, node.id)
    rescue => e
      ExceptionAlertService.new(e, '61e1b65e51fc9a78').perform
      SystemEvent.create!(
        message: "Failed to remove images from node",
        log_level: 'warn',
        data: {
          'node' => {
            'id' => node&.id,
            'name' => node&.label
          },
          'error' => e.message
        },
        event_code: '61e1b65e51fc9a78'
      )
    end

  end
end
