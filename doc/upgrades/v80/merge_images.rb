##
# This is a helper script that can be run in the `cstacks console`.
# It's purposes is to help migrate a bunch of images, into a single new image with multiple variants.
#
# Example: Suppose prior to v8 you had MariaDB 10.4, 10.5, 10.6, etc. Now, you can have a single MariaDB
# image, but with multiple versions (variants). Once you have the new MariaDB image setup with
# all the variants, you can use this script to merge all existing images (and their associated)
# deployed containers and dependents, into the new image.
#
#

dry_run = false # If true, will not perform any database changes and just output what it would do.
errors = [] # Check this for possible issues after running
old_images = [324,313] # Id of old images
new_image = ContainerImage.find(170) # the NEW image you're merging into

# The default variant for existing images tied to this new image.
previous_default_variant = new_image.image_variants.find_by registry_image_tag: "12-alpine"

# First, ensure all dependencies are correctly linked to their previous version.
# This is because it's OK to have a null default_variant_id, because then it will just choose
# the default variant for an image. If you're repurposing an existing image, you'll want to
# update all previous images to use the expected variant, rather than the new default.
new_image.required_by_parent.where(default_variant: nil).each do |dep|
  puts "Updated dep #{dep.id} variant to #{previous_default_variant.id}"
  dep.update_columns(default_variant_id: previous_default_variant.id) unless dry_run
end

# Now migrate the image to the new image and variant.
old_images.each do |oid|
  image = ContainerImage.find(oid)
  next if image.nil?
  puts "#{image.name}"

  if image.image_variants.count > 1 && image.parent_containers.exists?
    errors << "#{image.id} has dependencies that can't be automatically moved."
  elsif image.image_variants.count == 1 && image.parent_containers.exists?
    variant = image.image_variants.first
    new_variant = new_image.image_variants.find_by registry_image_tag: variant.registry_image_tag
    image.required_by_parent.each do |dep|
      puts "--#{dep.container_image.name} linked"
      dep.update_columns(requires_container_id: new_image.id, default_variant_id: new_variant.id) unless dry_run
    end
  end

  image.image_variants.each do |variant|
    puts "-#{variant.label} : #{variant.registry_image_tag}"
    new_variant = new_image.image_variants.find_by registry_image_tag: variant.registry_image_tag
    if new_variant.nil?
      puts "--not found, skipping."
      errors << variant.registry_image_tag
      next
    end
    variant.image_dependents.each do |dep|
      puts "--#{dep.container_image.name} linked"
      dep.update_columns(requires_container_id: new_image.id, default_variant_id: new_variant.id) unless dry_run
    end
    variant.container_services.each do |service|
      puts "--#{service.name}"
      service.update(image_variant: new_variant) unless dry_run
      service.env_params.each do |env|
        puts "---#{env.name}"
        new_parent_env = new_image.env_params.find_by name: env.name
        if new_parent_env.nil? && env.parent_param
          puts "----not found, skipping"
          env.update(parent_param: nil) unless dry_run
        elsif new_parent_env
          puts "----found #{new_parent_env.id}"
          env.update(parent_param: new_parent_env) unless dry_run
        end
      end
      service.setting_params.each do |setting|
        puts "---#{setting.name}"
        new_parent_setting = new_image.setting_params.find_by name: setting.name
        if new_parent_setting.nil? && setting.parent_param
          puts "----not found, skipping"
          setting.update(parent_param: nil) unless dry_run
        elsif new_parent_setting
          puts "----found #{new_parent_setting.id}"
          setting.update(parent_param: new_parent_setting) unless dry_run
        end
      end
      service.ingress_rules.each do |ingress|
        puts "---#{ingress.port}/#{ingress.proto}"
        new_parent_ingress = new_image.ingress_params.find_by port: ingress.port, proto: ingress.proto
        if new_parent_ingress.nil? && setting.parent_param
          puts "----not found, skipping"
          ingress.update(parent_param: nil) unless dry_run
        elsif new_parent_ingress
          puts "----found #{new_parent_ingress.id}"
          ingress.update(parent_param: new_parent_ingress) unless dry_run
        end
      end
    end
  end
end; 0
