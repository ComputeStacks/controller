namespace :containers do

  desc "Install Joomla Container"
  task joomla: :environment do

    if ContainerImage.find_by(name: 'joomla').nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      unless ContainerImage.where(name: 'mariadb-105').exists?
        Rake::Task['containers:mariadb:v105'].execute
      end
      mysql  = ContainerImage.find_by(name: 'mariadb-105')
      joomla = ContainerImage.create!(
        name:                     "joomla",
        label:                    "Joomla",
        description:              "Joomla",
        role:                     "joomla",
        role_class:               "web",
        can_scale:                true,
        container_image_provider: dhprovider,
        registry_image_path:      "cmptstks/joomla",
        registry_image_tag:       "latest",
        min_cpu:                  1,
        min_memory:               256,
        validated_tag: true,
        validated_tag_updated: Time.now
      )
      joomla.dependency_parents.create!(
        requires_container_id: mysql.id,
        bypass_auth_check:     true
      )
      joomla.ingress_params.create!(
        port:            80,
        proto:           'http',
        external_access: true
      )
      joomla.volumes.create!(
        label:             'joomla',
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
      joomla.env_params.create!(
        name:       'JOOMLA_DB_PASSWORD',
        param_type: 'variable',
        env_value:  'dep.mysql.parameters.settings.mysql_password'
      )
      joomla.env_params.create!(
        name:       'JOOMLA_DB_HOST',
        param_type: 'variable',
        env_value:  'dep.mysql.self.ip'
      )
      joomla.env_params.create!(
        name:       'JOOMLA_DB_NAME',
        param_type: 'variable',
        env_value:  'build.self.service_name_short'
      )
      joomla.env_params.create!(
        name:       'JOOMLA_DB_USER',
        param_type: 'static',
        env_value:  'root'
      )
    end

  end

end
