task pull_images: :environment do

  Node.online.each do |node|
    puts "Working on node #{node.label}"
    ContainerImage.where(user_id: nil).each do |i|
      image.image_variants.each do |variant|
        puts "...Updating image #{i.name}:#{variant.registry_image_tag}."
        NodeServices::PullImageService.new(node, variant).perform
      end
    end
  end

end
