namespace :containers do

  desc "Install wordpress container"
  task wordpress: :environment do

    if ContainerImage.find_by(name: 'wordpress').nil?
      provider = ContainerImageProvider.find_by(name: "Github")

      unless ContainerImage.where(name: 'mariadb').exists?
        Rake::Task['containers:mariadb'].execute
      end
      mysql = ContainerImage.find_by(name: 'mariadb')

      wp = ContainerImage.create!(
        name:                     "wordpress",
        label:                    "Wordpress",
        description:              "Wordpress with PHP FPM and nginx",
        role:                     "wordpress",
        category:               "web",
        can_scale:                true,
        container_image_provider: provider,
        registry_image_path:      "computestacks/cs-docker-wordpress",
        min_cpu:                  1,
        min_memory:               512,
        labels:                   {
          system_image_name: "wordpress-litespeed"
        },
        skip_variant_setup: true,
        active: false
      )

      unless ContainerImageCollection.where(label: 'Wordpress').exists?
        wpc = ContainerImageCollection.create!( label: 'Wordpress', active: true )
        wpc.container_images << mysql
        wpc.container_images << wp
      end

      wp.image_variants.create!(
        label: "php 7.4",
        registry_image_tag: "php7.4-nginx",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 2,
        skip_tag_validation: true
      )

      wp.image_variants.create!(
        label: "php 8.0",
        registry_image_tag: "php8.0-nginx",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 1,
        skip_tag_validation: true
      )

      wp.image_variants.create!(
        label: "php 8.1",
        registry_image_tag: "php8.1-nginx",
        validated_tag: true,
        validated_tag_updated: Time.now,
        is_default: false,
        version: 0,
        skip_tag_validation: true
      )

      wp.image_variants.create!(
        label: "php 8.2",
        registry_image_tag: "php8.2-nginx",
        validated_tag: true,
        validated_tag_updated: Time.now,
        is_default: true,
        version: 0,
        skip_tag_validation: true
      )

      wp.dependency_parents.create!(
        requires_container_id: mysql.id,
        bypass_auth_check:     true
      )
      wp.setting_params.create!(
        name:       'wordpress_password',
        label:      'Password',
        param_type: 'password'
      )
      wp.setting_params.create!(
        name:       'title',
        label:      'Title',
        param_type: 'static',
        value:      'My Blog'
      )
      wp.setting_params.create!(
        name:       'email',
        label:      'email',
        param_type: 'static',
        value:      'user@example.com'
      )
      wp.setting_params.create!(
        name:       'username',
        label:      'Username',
        param_type: 'static',
        value:      'admin'
      )
      wp.ingress_params.create!(
        port:            80,
        proto:           'http',
        external_access: true
      )
      wp.env_params.create!(
        name:       'CS_AUTH_KEY',
        param_type: 'variable',
        env_value:  'build.self.ec_pub_key'
      )
      wp.env_params.create!(
        name:       'WORDPRESS_DB_PASSWORD',
        param_type: 'variable',
        env_value:  'dep.mysql.parameters.settings.mysql_password'
      )
      wp.env_params.create!(
        name:       'WORDPRESS_DB_HOST',
        param_type: 'variable',
        env_value:  'dep.mysql.self.ip'
      )
      wp.env_params.create!(
        name:       'WORDPRESS_DB_NAME',
        param_type: 'variable',
        env_value:  'build.self.service_name_short'
      )
      wp.env_params.create!(
        name:       'WORDPRESS_URL',
        param_type: 'variable',
        env_value:  'build.self.default_domain'
      )
      wp.env_params.create!(
        name:       'WORDPRESS_TITLE',
        param_type: 'variable',
        env_value:  'build.settings.title'
      )
      wp.env_params.create!(
        name:       'WORDPRESS_USER',
        param_type: 'variable',
        env_value:  'build.settings.username'
      )
      wp.env_params.create!(
        name:       'WORDPRESS_PASSWORD',
        param_type: 'variable',
        env_value:  'build.settings.wordpress_password'
      )
      wp.env_params.create!(
        name:       'WORDPRESS_EMAIL',
        param_type: 'variable',
        env_value:  'build.settings.email'
      )
      wp.env_params.create!(
        name:         'WORDPRESS_DB_USER',
        param_type:   'static',
        static_value: 'root'
      )
      wp.volumes.create!(
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
    end

  end

end
