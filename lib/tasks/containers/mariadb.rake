namespace :containers do
  desc "MariaDB Container"
  task mariadb: :environment do
    mysql = ContainerImage.find_by(name: 'mariadb')
    if mysql.nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      mysql      = ContainerImage.create!(
        name:                     'mariadb',
        label:                    'MariaDB',
        role:                     'mysql',
        category:               'database',
        can_scale:                false,
        container_image_provider: dhprovider,
        registry_image_path:      "mariadb",
        command:                  "--max_allowed_packet=268435456",
        skip_variant_setup: true
      )

      mysql.image_variants.create!(
        label: "10.9",
        registry_image_tag: "10.9",
        validated_tag: true,
        validated_tag_updated: Time.now,
        is_default: true,
        version: 0,
        skip_tag_validation: true
      )

      mysql.image_variants.create!(
        label: "10.8",
        registry_image_tag: "10.8",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 1,
        skip_tag_validation: true
      )

      mysql.image_variants.create!(
        label: "10.7",
        registry_image_tag: "10.7",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 2,
        skip_tag_validation: true
      )

      mysql.image_variants.create!(
        label: "10.6",
        registry_image_tag: "10.6",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 3,
        skip_tag_validation: true
      )

      mysql.image_variants.create!(
        label: "10.5",
        registry_image_tag: "10.5",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 4,
        skip_tag_validation: true
      )

      mysql.setting_params.create!(
        name:       'mysql_password',
        label:      'Root Password',
        param_type: 'password'
      )
      mysql.env_params.create!(
        name:       'MYSQL_ROOT_PASSWORD',
        label:      'MYSQL_ROOT_PASSWORD',
        param_type: 'variable',
        env_value:  'build.settings.mysql_password'
      )
      mysql.env_params.create!(
        name: 'MARIADB_AUTO_UPGRADE',
        label: 'MARIADB_AUTO_UPGRADE',
        param_type: 'static',
        static_value: 'true'
      )
      mysql.ingress_params.create!(
        port:            3306,
        proto:           'tcp',
        external_access: false
      )
      mysql.volumes.create!(
        label:             'mysql',
        mount_path:        '/var/lib/mysql',
        enable_sftp:       false,
        borg_enabled:      true,
        borg_freq:         '@daily',
        borg_strategy:     'mysql',
        borg_keep_hourly:  1,
        borg_keep_daily:   7,
        borg_keep_weekly:  4,
        borg_keep_monthly: 0
      )
    end
  end
end
