namespace :dev do
  desc "Point dev container images (and the bastion) at a private registry"
  task private_images: :environment do
    raise "dev:private_images is for development only" if Rails.env.production?

    path = Rails.root.join(ENV.fetch("DEV_PRIVATE_IMAGES_FILE", "config/dev_private_images.yml"))
    unless File.exist?(path)
      puts "No #{path}; leaving container images on their public registries."
      next
    end

    config = YAML.safe_load_file(path) || {}
    registry = config["registry"].to_s.strip.sub(%r{\Ahttps?://}, "").chomp("/")
    username = ENV["DEV_REGISTRY_USERNAME"].to_s
    password = ENV["DEV_REGISTRY_PASSWORD"].to_s
    raise "#{path}: `registry` is required" if registry.blank?
    if username.blank? || password.blank?
      raise "Set DEV_REGISTRY_USERNAME and DEV_REGISTRY_PASSWORD in .envrc to pull from #{registry}"
    end

    if config["bastion"].present?
      puts "Bastion image -> #{config["bastion"]}"
      Setting.find_by(name: "cs_bastion_image").update!(value: config["bastion"])
    end

    (config["images"] || {}).each do |name, spec|
      image = ContainerImage.find_by(name: name)
      if image.nil?
        warn "No container image named #{name}; skipping (run db:seed first)."
        next
      end

      tags = Array(spec["tags"]).map(&:to_s)
      default_tag = (spec["default"] || tags.last).to_s
      raise "#{path}: #{name} needs at least one tag" if tags.empty?
      raise "#{path}: #{name} default #{default_tag} is not in its tags" unless tags.include?(default_tag)

      puts "#{name} -> #{registry}/#{spec["path"]} (#{tags.join(", ")}; default #{default_tag})"
      ContainerImage.transaction do
        image.update!(
          container_image_provider: nil,
          registry_custom: registry,
          registry_image_path: spec["path"],
          registry_auth: true,
          registry_username: username,
          registry_password: password
        )

        tags.each do |tag|
          next if image.image_variants.exists?(registry_image_tag: tag)

          image.image_variants.create!(
            label: tag,
            registry_image_tag: tag,
            validated_tag: true,
            validated_tag_updated: Time.now,
            skip_tag_validation: true
          )
        end

        image.image_variants.find_by!(registry_image_tag: default_tag).update!(is_default: true)

        # Tags the private registry doesn't carry would only fail to pull.
        # A variant something is deployed from refuses to go; keep it and say so.
        image.image_variants.where.not(registry_image_tag: tags).find_each do |stale|
          next if stale.destroy

          warn "  kept #{name}:#{stale.registry_image_tag}: #{stale.errors.full_messages.join(" ")}"
        end
      end
    end
  end
end
