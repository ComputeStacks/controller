namespace :containers do

  desc "Install ghost"
  task ghost: :environment do

    unless ContainerImage.where("labels @> ?", { system_image_name: "ghost-4" }.to_json).exists?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      ghost      = ContainerImage.create!(
        name:                     'ghost-4',
        label:                    'Ghost',
        role:                     'ghost',
        role_class:               'web',
        can_scale:                false,
        container_image_provider: dhprovider,
        registry_image_path:      "cmptstks/ghost",
        registry_image_tag:       "4",
        validated_tag: true,
        validated_tag_updated: Time.now,
        labels: {
          system_image_name: "ghost-4"
        }
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
