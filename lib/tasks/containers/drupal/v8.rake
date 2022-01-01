namespace :containers do

  namespace :drupal do

    desc "Install drupal v8 container"
    task v8: :environment do

      unless ContainerImage.where("labels @> ?", { system_image_name: "drupal-8" }.to_json).exists?
        dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
        unless ContainerImage.where(name: 'mariadb-105').exists?
          Rake::Task['containers:mariadb:v105'].execute
        end
        mysql = ContainerImage.find_by(name: 'mariadb-105')
        drupal = ContainerImage.create!(
          name: "drupal-8",
          label: "Drupal 8",
          description: "Drupal 8",
          role: "drupal",
          role_class: "web",
          can_scale: true,
          container_image_provider: dhprovider,
          registry_image_path: "bitnami/drupal",
          registry_image_tag: "8",
          min_cpu: 1,
          min_memory: 512,
          validated_tag: true,
          validated_tag_updated: Time.now,
          labels: {
            system_image_name: "drupal-8"
          }
        )
        drupal.dependency_parents.create!(
          requires_container_id: mysql.id,
          bypass_auth_check: true
        )
        drupal.ingress_params.create!(
          port: 8080,
          proto: 'http',
          external_access: true
        )
        drupal.setting_params.create!(
          name: 'drupal_password',
          label: 'Password',
          param_type: 'password'
        )
        drupal.setting_params.create!(
          name: 'drupal_db_pw',
          label: 'DB Password',
          param_type: 'password'
        )
        drupal.setting_params.create!(
          name: 'drupal_email',
          label: 'Email',
          param_type: 'static',
          value: 'user@example.com'
        )
        #
        ## Volumes
        drupal.volumes.create!(
          label: 'drupal',
          mount_path: '/bitnami/drupal',
          enable_sftp: true,
          borg_enabled: true,
          borg_freq: '@daily',
          borg_strategy: 'file',
          borg_keep_hourly: 1,
          borg_keep_daily: 7,
          borg_keep_weekly: 4,
          borg_keep_monthly: 0
        )
        drupal.env_params.create!(
          name: 'DRUPAL_PASSWORD',
          param_type: 'variable',
          env_value: 'build.settings.drupal_password'
        )
        drupal.env_params.create!(
          name: 'DRUPAL_DATABASE_NAME',
          param_type: 'variable',
          env_value: 'build.self.service_name_short'
        )
        drupal.env_params.create!(
          name: 'DRUPAL_EMAIL',
          param_type: 'variable',
          env_value: 'build.settings.drupal_email'
        )
        drupal.env_params.create!(
          name: 'MARIADB_HOST',
          param_type: 'variable',
          env_value: 'dep.mysql.self.ip'
        )
        drupal.env_params.create!(
          name: 'MARIADB_ROOT_PASSWORD',
          param_type: 'variable',
          env_value: 'dep.mysql.parameters.settings.mysql_password'
        )
        drupal.env_params.create!(
          name: 'MYSQL_CLIENT_CREATE_DATABASE_NAME',
          param_type: 'variable',
          env_value: 'build.self.service_name_short'
        )
        drupal.env_params.create!(
          name: 'DRUPAL_USERNAME',
          param_type: 'variable',
          env_value: 'build.settings.drupal_email'
        )
        drupal.env_params.create!(
          name: 'MYSQL_CLIENT_CREATE_DATABASE_USER',
          param_type: 'variable',
          env_value: 'build.self.service_name_short'
        )
        drupal.env_params.create!(
          name: 'DRUPAL_DATABASE_PASSWORD',
          param_type: 'variable',
          env_value: 'build.settings.drupal_password'
        )
        drupal.env_params.create!(
          name: 'MYSQL_CLIENT_CREATE_DATABASE_PASSWORD',
          param_type: 'variable',
          env_value: 'build.settings.drupal_password'
        )
        drupal.env_params.create!(
          name: 'DRUPAL_DATABASE_USER',
          param_type: 'variable',
          env_value: 'build.self.service_name_short'
        )

        ##
        # SMTP
        drupal.setting_params.create!(
          name: 'smtp_host',
          label: 'SMTP Host',
          param_type: 'static',
          value: 'smtp.postmarkapp.com'
        )
        drupal.setting_params.create!(
          name: 'smtp_port',
          label: 'SMTP Port',
          param_type: 'static',
          value: '587'
        )
        drupal.setting_params.create!(
          name: 'smtp_user',
          label: 'SMTP User',
          param_type: 'static',
          value: 'user'
        )
        drupal.setting_params.create!(
          name: 'smtp_password',
          label: 'SMTP Password',
          param_type: 'static',
          value: 'changeme'
        )
        drupal.setting_params.create!(
          name: 'smtp_proto',
          label: 'SMTP Protocol',
          param_type: 'static',
          value: 'tls'
        )
        drupal.env_params.create!(
          name: 'DRUPAL_SMTP_HOST',
          param_type: 'variable',
          env_value: 'build.settings.smtp_host'
        )
        drupal.env_params.create!(
          name: 'DRUPAL_SMTP_PORT',
          param_type: 'variable',
          env_value: 'build.settings.smtp_port'
        )
        drupal.env_params.create!(
          name: 'DRUPAL_SMTP_USER',
          param_type: 'variable',
          env_value: 'build.settings.smtp_user'
        )
        drupal.env_params.create!(
          name: 'DRUPAL_SMTP_PASSWORD',
          param_type: 'variable',
          env_value: 'build.settings.smtp_password'
        )
        drupal.env_params.create!(
          name: 'DRUPAL_SMTP_PROTOCOL',
          param_type: 'variable',
          env_value: 'build.settings.smtp_proto'
        )

      end

    end

  end

end
