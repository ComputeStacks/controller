namespace :containers do

  desc "Install woocommerce container"
  task woocommerce: :environment do

    if ContainerImage.find_by(name: 'woocommerce').nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      unless ContainerImage.where(name: 'mariadb-105').exists?
        Rake::Task['containers:mariadb:v105'].execute
      end
      mysql = ContainerImage.find_by(name: 'mariadb-105')
      woo   = ContainerImage.create!(
        name:                     "woocommerce",
        label:                    "WooCommerce",
        description:              "WooCommerce (Wordpress) powered by the OpenLiteSpeed web server. Includes advanced caching and performance tuning, with out of the box support for redis object cache and ElasticSearch (requires separate containers).",
        role:                     "wordpress",
        role_class:               "web",
        can_scale:                true,
        container_image_provider: dhprovider,
        registry_image_path:      "cmptstks/woocommerce",
        registry_image_tag:       "php7.4-litespeed",
        min_cpu:                  1,
        min_memory:               512,
        labels:                   {
          system_image_name: "woocommerce-litespeed"
        },
        validated_tag: true,
        validated_tag_updated: Time.now
      )
      woo.dependency_parents.create!(
        requires_container_id: mysql.id,
        bypass_auth_check:     true
      )
      woo.setting_params.create!(
        name:       'wordpress_password',
        label:      'Password',
        param_type: 'password'
      )
      woo.setting_params.create!(
        name:       'litespeed_admin_pw',
        label:      'Litespeed Password',
        param_type: 'password'
      )
      woo.setting_params.create!(
        name:       'title',
        label:      'Title',
        param_type: 'static',
        value:      'My Store'
      )
      woo.setting_params.create!(
        name:       'email',
        label:      'email',
        param_type: 'static',
        value:      'user@example.com'
      )
      woo.setting_params.create!(
        name:       'username',
        label:      'Username',
        param_type: 'static',
        value:      'admin'
      )
      woo.ingress_params.create!(
        port:            80,
        proto:           'http',
        external_access: true
      )
      woo.ingress_params.create!(
        port:            7080,
        proto:           'http',
        external_access: true,
        backend_ssl:     true
      )
      woo.env_params.create!(
        name:       'LS_ADMIN_PW',
        param_type: 'variable',
        env_value:  'build.settings.litespeed_admin_pw'
      )
      woo.env_params.create!(
        name:       'LS_ADMIN_PW',
        param_type: 'variable',
        env_value:  'build.settings.litespeed_admin_pw'
      )
      woo.env_params.create!(
        name:       'WORDPRESS_DB_PASSWORD',
        param_type: 'variable',
        env_value:  'dep.mysql.parameters.settings.mysql_password'
      )
      woo.env_params.create!(
        name:       'WORDPRESS_DB_HOST',
        param_type: 'variable',
        env_value:  'dep.mysql.self.ip'
      )
      woo.env_params.create!(
        name:       'WORDPRESS_DB_NAME',
        param_type: 'variable',
        env_value:  'build.self.service_name_short'
      )
      woo.env_params.create!(
        name:       'WORDPRESS_URL',
        param_type: 'variable',
        env_value:  'build.self.default_domain'
      )
      woo.env_params.create!(
        name:       'WORDPRESS_TITLE',
        param_type: 'variable',
        env_value:  'build.settings.title'
      )
      woo.env_params.create!(
        name:       'WORDPRESS_USER',
        param_type: 'variable',
        env_value:  'build.settings.username'
      )
      woo.env_params.create!(
        name:       'WORDPRESS_PASSWORD',
        param_type: 'variable',
        env_value:  'build.settings.wordpress_password'
      )
      woo.env_params.create!(
        name:       'WORDPRESS_EMAIL',
        param_type: 'variable',
        env_value:  'build.settings.email'
      )
      woo.env_params.create!(
        name:         'WORDPRESS_DB_USER',
        param_type:   'static',
        static_value: 'root'
      )
      woo.volumes.create!(
        label:             'wordpress',
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
      woo.volumes.create!(
        label:             'webconfig',
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
