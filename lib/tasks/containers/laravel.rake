namespace :containers do
  desc "Install laravel"
  task laravel: :environment do

    unless ContainerImage.find_by(name: 'laravel').exists?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      unless ContainerImage.where(name: 'mariadb').exists?
        Rake::Task['containers:mariadb'].execute
      end
      mysql   = ContainerImage.find_by(name: 'mariadb')
      laravel = ContainerImage.create!(
        name:                     'laravel',
        label:                    'Laravel',
        role:                     'laravel',
        category:               'web',
        can_scale:                true,
        container_image_provider: dhprovider,
        registry_image_path:      "cmptstks/laravel"
      )
      laravel.image_variants.create!(
        label: "5",
        registry_image_tag: "5",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true
      )
      laravel.dependency_parents.create!(
        requires_container_id: mysql.id,
        bypass_auth_check:     true
      )
      laravel.ingress_params.create!(
        port:            3000,
        proto:           'http',
        external_access: true
      )
      laravel.volumes.create!(
        label:             'laravelapp',
        mount_path:        '/app',
        enable_sftp:       true,
        borg_enabled:      true,
        borg_freq:         '@daily',
        borg_strategy:     'file',
        borg_keep_hourly:  1,
        borg_keep_daily:   7,
        borg_keep_weekly:  4,
        borg_keep_monthly: 0
      )
      laravel.env_params.create!(
        name:         'DB_USERNAME',
        param_type:   'static',
        static_value: 'root'
      )
      laravel.env_params.create!(
        name:       'DB_HOST',
        param_type: 'variable',
        env_value:  'dep.mysql.self.ip'
      )
      laravel.env_params.create!(
        name:       'DB_DATABASE',
        param_type: 'variable',
        env_value:  'build.self.service_name_short'
      )
      laravel.env_params.create!(
        name:       'DB_PASSWORD',
        param_type: 'variable',
        env_value:  'dep.mysql.parameters.settings.mysql_password'
      )
    end

  end

end
