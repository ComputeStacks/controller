namespace :containers do
  desc "Install php container"
  task php: :environment do
    if ContainerImage.find_by(name: 'php').nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      php        = ContainerImage.create!(
        name:                     'php',
        label:                    'PHP',
        description:              "PHP with OpenLiteSpeed",
        role:                     'php',
        category:               'web',
        can_scale:                true,
        is_free:                  false,
        container_image_provider: dhprovider,
        registry_image_path:      "cmptstks/php"
      )

      php.image_variants.create!(
        label: "php8.1-litespeed",
        registry_image_tag: "php8.1-litespeed",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )

      php.image_variants.create!(
        label: "php8.0-litespeed",
        registry_image_tag: "php8.0-litespeed",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 1,
        skip_tag_validation: true
      )

      php.image_variants.create!(
        label: "php7.4-litespeed",
        registry_image_tag: "php7.4-litespeed",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 2,
        skip_tag_validation: true
      )

      php.image_variants.create!(
        label: "php7.3-litespeed",
        registry_image_tag: "php7.4-litespeed",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 3,
        skip_tag_validation: true
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