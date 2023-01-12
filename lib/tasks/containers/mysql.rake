namespace :containers do
  desc "MySQL Container"
  task mariadb: :environment do
    mysql = ContainerImage.find_by(name: 'mysql')
    if mysql.nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      mysql = ContainerImage.create!(
        name: 'mysql',
        label: 'MySQL',
        role: 'mysql',
        category: 'database',
        can_scale: false,
        container_image_provider: dhprovider,
        registry_image_path: "mysql",
        skip_variant_setup: true
      )

      ##
      # # A note about v8+.
      # Each minor change (e.g. 8.0.30 to 8.0.31) requires Percona xtrabackup
      # to support it, which can lag behind the official release of the v8.0 tag.
      # Therefore to prevent auto-upgrades to newer versions before our backup agent
      # can support it, we will lock MySQL to the 3rd point release.
      #
      # Users can upgrade automatically in ComputeStacks by editing their service,
      # and choosing the new release once it's available.
      #
      # Note that this is not the case with MariaDB, as it ships with it's own mariabackup
      # service pre-installed and does not require percona xtrabackup to be used separately.
      mysql.image_variants.create!(
        label: "8.0.30",
        registry_image_tag: "8.0.30",
        validated_tag: true,
        validated_tag_updated: Time.now,
        is_default: true,
        version: 0,
        skip_tag_validation: true
      )

      mysql.image_variants.create!(
        label: "5.7",
        registry_image_tag: "5.7",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 1,
        skip_tag_validation: true
      )

      mysql.setting_params.create!(
        name: 'mysql_password',
        label: 'Root Password',
        param_type: 'password'
      )
      mysql.env_params.create!(
        name: 'MYSQL_ROOT_PASSWORD',
        label: 'MYSQL_ROOT_PASSWORD',
        param_type: 'variable',
        env_value: 'build.settings.mysql_password'
      )
      mysql.ingress_params.create!(
        port: 3306,
        proto: 'tcp',
        external_access: false
      )
      mysql.volumes.create!(
        label: 'mysql',
        mount_path: '/var/lib/mysql',
        enable_sftp: false,
        borg_enabled: true,
        borg_freq: '@daily',
        borg_strategy: 'mysql',
        borg_keep_hourly: 1,
        borg_keep_daily: 7,
        borg_keep_weekly: 4,
        borg_keep_monthly: 0
      )
    end
  end
end
