namespace :containers do

  desc "Install phpMyAdmin Container"
  task pma: :environment do

    if ContainerImage.find_by(name: 'pma').nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      pma        = ContainerImage.create!(
        name:                     "pma",
        label:                    "phpMyAdmin",
        description:              "phpMyAdmin",
        role:                     "pma",
        category:               "dev",
        is_free:                  true,
        can_scale:                false,
        container_image_provider: dhprovider,
        registry_image_path:      "cmptstks/phpmyadmin"
      )
      pma.image_variants.create!(
        label: "v2",
        registry_image_tag: "v2",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )
      pma.ingress_params.create!(
        port:            80,
        proto:           'http',
        external_access: true
      )
      pma.ingress_params.create!(
        port:            7080,
        proto:           'http',
        external_access: true,
        backend_ssl:     true
      )
      pma.setting_params.create!(
        name:       'litespeed_admin_pw',
        label:      'Litespeed Password',
        param_type: 'password'
      )
      pma.env_params.create!(
        name:       'LS_ADMIN_PW',
        param_type: 'variable',
        env_value:  'build.settings.litespeed_admin_pw'
      )
      pma.volumes.create!(
        label:             'litespeed-config',
        mount_path:        '/usr/local/lsws',
        enable_sftp:       false,
        borg_enabled:      false
      )
    end

  end

end
