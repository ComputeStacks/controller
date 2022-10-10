namespace :containers do

  desc "Install ghost"
  task ghost: :environment do

    unless ContainerImage.where(name: "ghost").exists?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      ghost      = ContainerImage.create!(
        name:                     'ghost',
        label:                    'Ghost',
        role:                     'ghost',
        category:                 'web',
        can_scale:                false,
        container_image_provider: dhprovider,
        registry_image_path:      "cmptstks/ghost",
        skip_variant_setup: true
      )
      ghost.image_variants.create!(
        label: "4",
        registry_image_tag: "4",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )
      ghost.ingress_params.create!(
        port:            2368,
        proto:           'http',
        external_access: true
      )
      ghost.volumes.create!(
        label:             'ghost',
        mount_path:        '/var/lib/ghost/content',
        enable_sftp:       true,
        borg_enabled:      true,
        borg_freq:         '@daily',
        borg_strategy:     'file',
        borg_keep_hourly:  1,
        borg_keep_daily:   7,
        borg_keep_weekly:  4,
        borg_keep_monthly: 0
      )
      ghost.env_params.create!(
        name:       'url',
        param_type: 'variable',
        env_value:  'build.self.default_domain_with_proto'
      )
    end

  end

end
