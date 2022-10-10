namespace :containers do
  desc "Install postgres container"
  task postgres: :environment do

    unless ContainerImage.where(name: 'postgres').exists?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      pg         = ContainerImage.create!(
        name:                     'postgres',
        label:                    'PostgreSQL',
        role:                     'postgres',
        category:               'database',
        can_scale:                false,
        is_free:                  false,
        container_image_provider: dhprovider,
        registry_image_path:      "postgres",
        skip_variant_setup: true
      )
      pg.image_variants.create!(
        label: "14",
        registry_image_tag: "14",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )
      pg.image_variants.create!(
        label: "13",
        registry_image_tag: "13",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 1,
        skip_tag_validation: true
      )
      pg.image_variants.create!(
        label: "12",
        registry_image_tag: "12",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 2,
        skip_tag_validation: true
      )
      pg.image_variants.create!(
        label: "11-bullseye",
        registry_image_tag: "11-bullseye",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 3,
        skip_tag_validation: true
      )
      pg.image_variants.create!(
        label: "10",
        registry_image_tag: "10-bullseye",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 4,
        skip_tag_validation: true
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
