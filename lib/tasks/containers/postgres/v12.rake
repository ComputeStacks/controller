namespace :containers do

  namespace :postgres do

    desc "Install postgres 12 container"
    task v12: :environment do

      if ContainerImage.find_by(name: 'postgres-12').nil?
        dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
        pg         = ContainerImage.create!(
          name:                     'postgres-12',
          label:                    'PostgreSQL 12',
          role:                     'postgres',
          role_class:               'database',
          can_scale:                false,
          is_free:                  false,
          container_image_provider: dhprovider,
          registry_image_path:      "postgres",
          registry_image_tag:       "12-alpine",
          validated_tag: true,
          validated_tag_updated: Time.now
        )
        pg.ingress_params.create!(
          port:            5432,
          proto:           'tcp',
          external_access: false
        )
        pg.volumes.create!(
          label:             'data',
          mount_path:        '/var/lib/postgresql/data',
          enable_sftp:       false,
          borg_enabled:      true,
          borg_freq:         '@daily',
          borg_strategy:     'postgres',
          borg_keep_hourly:  1,
          borg_keep_daily:   7,
          borg_keep_weekly:  4,
          borg_keep_monthly: 0
        )
        pg.setting_params.create!(
          name:       'postgres_password',
          label:      'Password',
          param_type: 'password'
        )
        pg.env_params.create!(
          name:         'POSTGRES_USER',
          label:        'Username',
          param_type:   'static',
          static_value: 'postgres'
        )
        pg.env_params.create!(
          name:       'POSTGRES_PASSWORD',
          label:      'Password',
          param_type: 'variable',
          env_value:  'build.settings.postgres_password'
        )
      end

    end

  end

end
