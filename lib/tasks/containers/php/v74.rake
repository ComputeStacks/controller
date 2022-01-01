namespace :containers do

  namespace :php do

    desc "Install php 7.4 container"
    task v74: :environment do
      if ContainerImage.find_by(name: 'php-7-4').nil?
        dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
        php        = ContainerImage.create!(
          name:                     'php-7-4',
          label:                    'PHP 7.4',
          description:              "PHP 7.4 with OpenLiteSpeed",
          role:                     'php',
          role_class:               'web',
          can_scale:                true,
          is_free:                  false,
          container_image_provider: dhprovider,
          registry_image_path:      "cmptstks/php",
          registry_image_tag:       "7.4-litespeed",
          validated_tag: true,
          validated_tag_updated: Time.now
        )
        php.setting_params.create!(
          name:       'litespeed_admin_pw',
          label:      'Litespeed Password',
          param_type: 'password'
        )
        php.env_params.create!(
          name:       'LS_ADMIN_PW',
          param_type: 'variable',
          env_value:  'build.settings.litespeed_admin_pw'
        )
        php.ingress_params.create!(
          port:            80,
          proto:           'http',
          external_access: true
        )
        php.ingress_params.create!(
          port:            7080,
          proto:           'http',
          external_access: true,
          backend_ssl:     true
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
        php.volumes.create!(
          label:             'litespeed-config',
          mount_path:        '/usr/local/lsws',
          enable_sftp:       false,
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
