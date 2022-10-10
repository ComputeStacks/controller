namespace :containers do
  desc "Install NodeJS"
  task nodejs: :environment do
    if ContainerImage.find_by(name: 'node').nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      nodejs     = ContainerImage.create!(
        name:                     "node",
        label:                    "Node",
        role:                     "node",
        category:               "web",
        can_scale:                true,
        container_image_provider: dhprovider,
        registry_image_path:      "cmptstks/node",
        skip_variant_setup: true
      )

      nodejs.image_variants.create!(
        label: "9",
        registry_image_tag: "9",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )

      nodejs.ingress_params.create!(
        port:            3000,
        proto:           'http',
        external_access: true
      )
      nodejs.volumes.create!(
        label:             'nodeapp',
        mount_path:        '/usr/src/app',
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
