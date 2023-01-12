namespace :containers do
  desc "Install php 7.2 container"
  task whmcs: :environment do

    if ContainerImage.find_by(name: 'whmcs').nil?

      unless ContainerImage.where(name: 'mariadb').exists?
        Rake::Task['containers:mariadb'].execute
      end
      mysql = ContainerImage.find_by(name: 'mariadb')

      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      whmcs      = ContainerImage.create!(
        name:                     'whmcs',
        label:                    'WHMCS',
        description:              "WHMCS is a web hosting automation and billing engine.",
        role:                     'whmcs',
        category:               'web',
        can_scale:                true,
        is_free:                  false,
        container_image_provider: dhprovider,
        registry_image_path:      "ghcr.io/computestacks/cs-docker-whmcs",
        skip_variant_setup: true
      )

      whmcs.image_variants.create!(
        label: "php 7.4",
        registry_image_tag: "php7.4-litespeed",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )

      whmcs.dependency_parents.create!(
        requires_container_id: mysql.id,
        bypass_auth_check:     true
      )
      whmcs.setting_params.create!(
        name:       'litespeed_admin_pw',
        label:      'Litespeed Password',
        param_type: 'password'
      )
      whmcs.env_params.create!(
        name:       'LS_ADMIN_PW',
        param_type: 'variable',
        env_value:  'build.settings.litespeed_admin_pw'
      )
      whmcs.env_params.create!(
        name:       'DB_PASSWORD',
        param_type: 'variable',
        env_value:  'dep.mysql.parameters.settings.mysql_password'
      )
      whmcs.env_params.create!(
        name:       'DB_HOST',
        param_type: 'variable',
        env_value:  'dep.mysql.self.ip'
      )
      whmcs.env_params.create!(
        name:       'DB_NAME',
        param_type: 'variable',
        env_value:  'build.self.service_name_short'
      )
      whmcs.env_params.create!(
        name:         'DB_USER',
        param_type:   'static',
        static_value: 'root'
      )
      whmcs.ingress_params.create!(
        port:            80,
        proto:           'http',
        external_access: true
      )
      whmcs.ingress_params.create!(
        port:            7080,
        proto:           'http',
        external_access: true,
        backend_ssl:     true
      )
      whmcs.volumes.create!(
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
      whmcs.volumes.create!(
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
