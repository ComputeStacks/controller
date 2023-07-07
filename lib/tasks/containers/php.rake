namespace :containers do
  desc "Install php container"
  task php: :environment do
    if ContainerImage.find_by(name: 'php').nil?
      dhprovider = ContainerImageProvider.find_by(name: "Github")
      php        = ContainerImage.create!(
        name:                     'php',
        label:                    'PHP',
        description:              "PHP FPM with nginx",
        role:                     'php',
        category:                 'web',
        can_scale:                true,
        is_free:                  false,
        container_image_provider: dhprovider,
        registry_image_path:      "computestacks/cs-docker-php",
        skip_variant_setup: true
      )

      php.image_variants.create!(
        label: "8.2",
        registry_image_tag: "8.2-nginx",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )

      php.image_variants.create!(
        label: "8.1",
        registry_image_tag: "8.1-nginx",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: false,
        skip_tag_validation: true
      )

      php.image_variants.create!(
        label: "8.0",
        registry_image_tag: "8.0-nginx",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 1,
        skip_tag_validation: true
      )

      php.image_variants.create!(
        label: "7.4",
        registry_image_tag: "7.4-nginx",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 2,
        skip_tag_validation: true
      )
      php.ingress_params.create!(
        port:            80,
        proto:           'http',
        external_access: true
      )
      php.volumes.create!(
        label:             'webroot',
        mount_path:        '/var/www',
        enable_sftp:       true,
        borg_enabled:      true,
        borg_freq:         '@daily',
        borg_strategy:     'file',
        borg_keep_hourly:  1,
        borg_keep_daily:   7,
        borg_keep_weekly:  4,
        borg_keep_monthly: 0
      )
    end

  end

end
