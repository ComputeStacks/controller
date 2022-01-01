namespace :containers do
  namespace :mariadb do
    desc "MariaDB 10.5 Container"
    task v105: :environment do
      mysql = ContainerImage.find_by(name: 'mariadb-105')
      if mysql.nil?
        dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
        mysql      = ContainerImage.create!(
          name:                     'mariadb-105',
          label:                    'MariaDB 10.5',
          role:                     'mysql',
          role_class:               'database',
          can_scale:                false,
          container_image_provider: dhprovider,
          registry_image_path:      "mariadb",
          registry_image_tag:       "10.5",
          command:                  "--max_allowed_packet=268435456",
          validated_tag: true,
          validated_tag_updated: Time.now
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
end
