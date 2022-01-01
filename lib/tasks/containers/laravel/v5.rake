namespace :containers do

  namespace :laravel do

    desc "Install laravel v5"
    task v5: :environment do

      if ContainerImage.find_by(name: 'laravel-5').nil?
        dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
        unless ContainerImage.where(name: 'mariadb-105').exists?
          Rake::Task['containers:mariadb:v105'].execute
        end
        mysql   = ContainerImage.find_by(name: 'mariadb-105')
        laravel = ContainerImage.create!(
          name:                     'laravel-5',
          label:                    'Laravel 5',
          role:                     'laravel',
          role_class:               'web',
          can_scale:                true,
          container_image_provider: dhprovider,
          registry_image_path:      "cmptstks/laravel",
          registry_image_tag:       "5"
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

end
