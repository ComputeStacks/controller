module ImageWorkers
  class PullImageWorker
    include Sidekiq::Worker

    sidekiq_options retry: 2, queue: 'dep_critical'

    def perform(node_id, image_or_variant)
      obj = GlobalID::Locator.locate image_or_variant
      return if obj.nil?

      if obj.is_a?(ContainerImage)
        obj.image_variants.each do |i|
          perform_pull node_id, i
        end
      elsif obj.is_a?(ContainerImage::ImageVariant)
        perform_pull node_id, obj
      end
    rescue ActiveRecord::RecordNotFound
      return
    end

    private

    def perform_pull(node_id, variant)
      # For nil node_id and nodes less than 6,
      # we will process in serial.
      #
      # For nodes greater than 6, we will process in parallel.
      if node_id.blank?
        if Node.online.count < 6
          Node.online.each do |n|
            NodeServices::PullImageService.new(n, variant).perform
          end
          return
        end

        # Try to space out the image pulls
        count = 0
        delay = 30.seconds
        Node.online.each do |n|
          if count > 10
            ImageWorkers::PullImageWorker.perform_in delay, n.id, variant.to_global_id.to_s
            # every 10, increase delay by 15 seconds to evenly distribute
            delay += 15.seconds if count % 10 == 0
          else
            ImageWorkers::PullImageWorker.perform_async n.id, variant.to_global_id.to_s
          end
          count += 1
        end

        return
      end

      # Otherwise, perform job for single node
      node = Node.online.find_by(id: node_id)
      return if node.nil?
      NodeServices::PullImageService.new(node, variant).perform
    end

  end
end
