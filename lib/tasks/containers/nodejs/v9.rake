namespace :containers do

  namespace :nodejs do

    desc "Install NodeJS 9"
    task v9: :environment do
      if ContainerImage.find_by(name: 'node-9').nil?
        dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
        nodejs     = ContainerImage.create!(
          name:                     "node-9",
          label:                    "Node 9",
          role:                     "node",
          role_class:               "web",
          can_scale:                true,
          container_image_provider: dhprovider,
          registry_image_path:      "cmptstks/node",
          registry_image_tag:       "9",
          validated_tag: true,
          validated_tag_updated: Time.now
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
end
