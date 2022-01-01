namespace :containers do

  desc "Install Nextcloud"
  task nextcloud: :environment do

    if ContainerImage.find_by(name: 'nextcloud').nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")

      unless ContainerImage.where(name: 'mariadb-105').exists?
        Rake::Task['containers:mariadb:v105'].execute
      end
      mysql = ContainerImage.find_by(name: 'mariadb-105')

      unless ContainerImage.where(name: 'redis').exists?
        Rake::Task['containers:redis'].execute
      end
      redis = ContainerImage.find_by(name: 'redis')

      nextcloud = ContainerImage.create!(
        name:                     'nextcloud',
        label:                    'Nextcloud',
        role:                     'nextcloud',
        role_class:               'web',
        can_scale:                true,
        container_image_provider: dhprovider,
        registry_image_path:      "nextcloud",
        registry_image_tag:       "latest",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true
      )
      nextcloud.dependency_parents.create!(
        requires_container_id: mysql.id,
        bypass_auth_check:     true
      )
      nextcloud.dependency_parents.create!(
        requires_container_id: redis.id,
        bypass_auth_check:     true
      )
      nextcloud.ingress_params.create!(
        port:            80,
        proto:           'http',
        external_access: true
      )
      nextcloud.volumes.create!(
        label:             'webroot',
        mount_path:        '/var/www/html',
        enable_sftp:       false,
        borg_enabled:      true,
        borg_freq:         '@daily',
        borg_strategy:     'file',
        borg_keep_hourly:  1,
        borg_keep_daily:   7,
        borg_keep_weekly:  4,
        borg_keep_monthly: 0
      )
      nextcloud.setting_params.create!(
        name:       'password',
        label:      'Password',
        param_type: 'password'
      )
      nextcloud.setting_params.create!(
        name:       'username',
        label:      'Username',
        param_type: 'static',
        value:      'admin'
      )
      nextcloud.env_params.create!(
        name:       'MYSQL_DATABASE',
        param_type: 'variable',
        env_value:  'build.self.service_name_short'
      )
      nextcloud.env_params.create!(
        name:       'MYSQL_HOST',
        param_type: 'variable',
        env_value:  'dep.mysql.self.ip'
      )
      nextcloud.env_params.create!(
        name:       'MYSQL_PASSWORD',
        param_type: 'variable',
        env_value:  'dep.mysql.parameters.settings.mysql_password'
      )
      nextcloud.env_params.create!(
        name:       'NEXTCLOUD_ADMIN_PASSWORD',
        param_type: 'variable',
        env_value:  'build.settings.password'
      )
      nextcloud.env_params.create!(
        name:       'NEXTCLOUD_ADMIN_USER',
        param_type: 'variable',
        env_value:  'build.settings.username'
      )
      nextcloud.env_params.create!(
        name:       'NEXTCLOUD_TRUSTED_DOMAINS',
        param_type: 'variable',
        env_value:  'build.self.default_domain'
      )
      nextcloud.env_params.create!(
        name:       'REDIS_HOST',
        param_type: 'variable',
        env_value:  'dep.redis.self.ip'
      )
      nextcloud.env_params.create!(
        name:       'REDIS_HOST_PASSWORD',
        param_type: 'variable',
        env_value:  'dep.redis.parameters.settings.password'
      )
      nextcloud.env_params.create!(
        name:         'MYSQL_USER',
        param_type:   'static',
        static_value: 'root'
      )
      nextcloud.env_params.create!(
        name:         'OVERWRITEPROTOCOL',
        param_type:   'static',
        static_value: 'https'
      )
    end

  end

end
