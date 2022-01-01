namespace :containers do

  desc "Install nginx"
  task nginx: :environment do

    if ContainerImage.find_by(name: 'nginx').nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      nginx      = ContainerImage.create!(
        name:                     'nginx',
        label:                    'nginx',
        role:                     'nginx',
        role_class:               'web',
        can_scale:                true,
        container_image_provider: dhprovider,
        registry_image_path:      "cmptstks/nginx",
        registry_image_tag:       "stable",
        validated_tag: true,
        validated_tag_updated: Time.now
      )
      nginx.ingress_params.create!(
        port:            80,
        proto:           'http',
        external_access: true
      )
      nginx.volumes.create!(
        label:             'webroot',
        mount_path:        '/var/www/html',
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
