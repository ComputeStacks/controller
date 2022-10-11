namespace :containers do

  desc "Install memcache"
  task memcached: :environment do
    if ContainerImage.find_by(name: 'memcache').nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      memcache   = ContainerImage.create!(
        name:                     "memcache",
        label:                    "Memcache",
        description:              "Memcached is an in-memory key-value store for small chunks of arbitrary data (strings, objects) from results of database calls, API calls, or page rendering.",
        role:                     "memcached",
        category:               "web",
        can_scale:                false,
        container_image_provider: dhprovider,
        registry_image_path:      "memcached",
        skip_variant_setup: true
      )
      memcache.image_variants.create!(
        label: "latest",
        registry_image_tag: "alpine",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )
      memcache.ingress_params.create!(
        port:  11211,
        proto: 'tcp'
      )
    end
  end

end
