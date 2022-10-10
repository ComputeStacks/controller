namespace :containers do

  desc "Install grafana"
  task grafana: :environment do

    if ContainerImage.find_by(name: 'grafana').nil?
      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      graf = ContainerImage.create!(
        name: 'grafana',
        label: 'grafana',
        role: 'grafana',
        category: 'web',
        can_scale: false,
        container_image_provider: dhprovider,
        registry_image_path: "grafana/grafana",
        skip_variant_setup: true
      )
      graf.image_variants.create!(
        label: "latest",
        registry_image_tag: "latest",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )
      graf.setting_params.create!(
        name: 'plugins',
        label: 'Pre-Install Plugins',
        param_type: 'static',
        value: 'grafana-clock-panel,grafana-simple-json-datasource'
      )
      graf.env_params.create!(
        name: 'GF_INSTALL_PLUGINS',
        param_type: 'variable',
        env_value: 'build.settings.plugins'
      )
      graf.ingress_params.create!(
        port: 3000,
        proto: 'http',
        external_access: true
      )
      graf.volumes.create!(
        label: 'grafana',
        mount_path: '/var/lib/grafana',
        enable_sftp: false,
        borg_enabled: true,
        borg_freq: '@daily',
        borg_strategy: 'file',
        borg_keep_hourly: 1,
        borg_keep_daily: 7,
        borg_keep_weekly: 1,
        borg_keep_monthly: 0
      )
    end

  end

end
