namespace :containers do

  desc "Install magento 2.4 container"
  task magento: :environment do

    unless ContainerImage.where(name: 'magento-ce').exists?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      unless ContainerImage.where(name: 'mariadb').exists?
        Rake::Task['containers:mariadb'].execute
      end
      unless ContainerImage.where(name: "elasticsearch").exists?
        Rake::Task['containers:elasticsearch'].execute
      end
      mysql = ContainerImage.find_by(name: 'mariadb')
      es = ContainerImage.find_by(name: "elasticsearch")

      mage_block = Block.find_by(title: 'Magento 2 Setup')

      if mage_block.nil?
        puts "Creating Magento 2 custom content block"
        mage_block = Block.create!(title: 'Magento 2 Setup')
        mage_block.block_contents.create!(
          locale: ENV['LOCALE'],
          body:   "<h4>Magento CE 2 Overview</h4><div><br>Your Magento 2 image comes pre-loaded with:</div><ul><li>Postfix (with sendmail support) that automatically forwards your outgoing mail through your SMTP provider of choice.</li><li>Magento cron support</li><li>Log rotate enabled for magento log files</li><li>SSH access (username is&nbsp;<em>user</em>)<ul><li>This allows you to access the&nbsp;<em>bin/magento</em> command line tool from&nbsp;<em>/var/www/html/magento.</em></li><li>To connect over SSH, either generate a public port for the specific container, or access it over the private ip using your SSH/SFTP credentials.</li></ul></li></ul><div><br></div><h4>Initial Setup</h4><div><br>On first boot, magento 2 requires some additional time to perform the initial installation and configuration.&nbsp;<br><br>To watch the progress, please navigate to the container logs page. Once you see the following, then the application is ready to use.<br><br></div><pre>[OK] litespeed: pid=31159.\r\n*** Booting runit daemon...\r\n*** Runit started as PID 31187</pre><div><br><em>Note: It may appear to be stuck on setting file and folder permissions, but please be patient and allow that to run completely before attempting to restart or rebuild the container.</em><br><br><br></div><h4>Configuring your domain</h4><div><br>Please point your domain to the following IP Address:</div>"
        )
      end

      mage = ContainerImage.create!(
        name:                     "magento-ce",
        label:                    "Magento CE",
        description:              "Magento CE",
        role:                     "magento",
        category:               "web",
        can_scale:                true,
        container_image_provider: dhprovider,
        registry_image_path:      "cmptstks/magento-ce",
        min_cpu:                  1,
        min_memory:               1024,
        general_block_id:         mage_block.id
      )
      mage.image_variants.create!(
        label: "2.4",
        registry_image_tag: "2.4",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )
      mage.dependency_parents.create!(
        requires_container_id: mysql.id,
        bypass_auth_check:     true
      )
      mage.dependency_parents.create!(
        requires_container_id: es.id,
        bypass_auth_check:     true
      )
      mage.setting_params.create!(
        name:       'ssh_password',
        label:      'SSH Password',
        param_type: 'password'
      )
      mage.setting_params.create!(
        name:       'mage_password',
        label:      'Magento PW',
        param_type: 'password'
      )
      mage.setting_params.create!(
        name:       'ls_admin_password',
        label:      'Litespeed PW',
        param_type: 'password'
      )
      mage.setting_params.create!(
        name:       'timezone',
        label:      'TZ',
        param_type: 'static',
        value:      'America/Los_Angeles'
      )
      mage.setting_params.create!(
        name:       'email',
        label:      'Email',
        param_type: 'static',
        value:      'user@example.com'
      )
      mage.setting_params.create!(
        name:       'currency',
        label:      'Currency',
        param_type: 'static',
        value:      'USD'
      )
      mage.setting_params.create!(
        name:       'smtp_server',
        label:      'SMTP Server',
        param_type: 'static',
        value:      'smtp.postmarkapp.com'
      )
      mage.setting_params.create!(
        name:       'smtp_username',
        label:      'SMTP Username',
        param_type: 'static',
        value:      'change-me'
      )
      mage.setting_params.create!(
        name:       'smtp_password',
        label:      'SMTP Password',
        param_type: 'static',
        value:      'change-me'
      )
      mage.setting_params.create!(
        name:       'smtp_port',
        label:      'SMTP Port',
        param_type: 'static',
        value:      '2525'
      )
      mage.ingress_params.create!(
        port:            22,
        proto:           'tcp',
        external_access: false
      )
      mage.ingress_params.create!(
        port:            80,
        proto:           'http',
        external_access: true
      )
      mage.ingress_params.create!(
        port:            7080,
        proto:           'http',
        external_access: true,
        backend_ssl:     true
      )
      mage.env_params.create!(
        name:       'LS_ADMIN_PW',
        param_type: 'variable',
        env_value:  'build.settings.ls_admin_password'
      )
      mage.env_params.create!(
        name:       'SSH_PASS',
        param_type: 'variable',
        env_value:  'build.settings.ssh_password'
      )
      mage.env_params.create!(
        name:       'MYSQL_HOST',
        param_type: 'variable',
        env_value:  'dep.mysql.self.ip'
      )
      mage.env_params.create!(
        name:       'ES_HOST',
        param_type: 'variable',
        env_value:  'dep.elasticsearch.self.ip'
      )
      mage.env_params.create!(
        name:         'MYSQL_USER',
        param_type:   'static',
        static_value: 'root'
      )
      mage.env_params.create!(
        name:       'MYSQL_PW',
        param_type: 'variable',
        env_value:  'dep.mysql.parameters.settings.mysql_password'
      )
      mage.env_params.create!(
        name:       'MYSQL_DB_NAME',
        param_type: 'variable',
        env_value:  'build.self.service_name_short'
      )
      mage.env_params.create!(
        name:       'DEFAULT_DOMAIN',
        param_type: 'variable',
        env_value:  'build.self.default_domain'
      )
      mage.env_params.create!(
        name:         'PROTO',
        param_type:   'static',
        static_value: 'https'
      )
      mage.env_params.create!(
        name:         'MAGE_USERNAME',
        param_type:   'static',
        static_value: 'admin'
      )
      mage.env_params.create!(
        name:       'MAGE_PW',
        param_type: 'variable',
        env_value:  'build.settings.mage_password'
      )
      mage.env_params.create!(
        name:       'TIMEZONE',
        param_type: 'variable',
        env_value:  'build.settings.timezone'
      )
      mage.env_params.create!(
        name:       'MAGE_EMAIL',
        param_type: 'variable',
        env_value:  'build.settings.email'
      )
      mage.env_params.create!(
        name:       'CURRENCY',
        param_type: 'variable',
        env_value:  'build.settings.currency'
      )
      mage.env_params.create!(
        name:       'SMTP_SERVER',
        param_type: 'variable',
        env_value:  'build.settings.smtp_server'
      )
      mage.env_params.create!(
        name:       'SMTP_USERNAME',
        param_type: 'variable',
        env_value:  'build.settings.smtp_username'
      )
      mage.env_params.create!(
        name:       'SMTP_PASSWORD',
        param_type: 'variable',
        env_value:  'build.settings.smtp_password'
      )
      mage.env_params.create!(
        name:       'SMTP_PORT',
        param_type: 'variable',
        env_value:  'build.settings.smtp_port'
      )
      mage.volumes.create!(
        label:             'magento',
        mount_path:        '/var/www',
        enable_sftp:       true,
        borg_enabled:      true,
        borg_freq:         '@daily',
        borg_strategy:     'file',
        borg_keep_hourly:  1,
        borg_keep_daily:   7,
        borg_keep_weekly:  4,
        borg_keep_monthly: 0,
        borg_keep_annually: 0
      )
      mage.volumes.create!(
        label:             'webconfig',
        mount_path:        '/usr/local/lsws',
        enable_sftp:       false,
        borg_enabled:      true,
        borg_freq:         '@daily',
        borg_strategy:     'file',
        borg_keep_hourly:  1,
        borg_keep_daily:   7,
        borg_keep_weekly:  4,
        borg_keep_monthly: 0,
        borg_keep_annually: 0
      )

    end


  end

end
