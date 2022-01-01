task pull_images: :environment do

  Node.online.each do |node|
    puts "Working on node #{node.label}"
    ContainerImage.where(user_id: nil).each do |i|
      puts "...Updating image #{i.name}."
      NodeServices::PullImageService.new(node, i).perform
    end
  end

end
