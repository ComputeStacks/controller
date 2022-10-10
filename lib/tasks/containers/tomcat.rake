namespace :containers do

  desc "Install tomcat container"
  task tomcat: :environment do
    if ContainerImage.find_by(name: 'tomcat').nil?

      # Setup block
      block = Block.create!(title: 'Tomcat Image', content_key: 'tomcat_general')
      block.block_contents.create!(
        locale: ENV['LOCALE'],
        body: "<h4>Tomcat</h4><div><br></div><div>To learn how to use this image, please visit: <a href=\"https://github.com/ComputeStacks/docker/blob/master/tomcat/README.md\">https://github.com/ComputeStacks/docker/blob/master/tomcat/README.md</a></div>"
      )

      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      tomcat = ContainerImage.create!(
        label: 'Tomcat 10',
        name: 'tomcat-10',
        description: 'Tomcat image',
        role: 'tomcat',
        category: 'web',
        can_scale: true,
        is_free: false,
        container_image_provider: dhprovider,
        registry_image_path: "cmptstks/tomcat",
        general_block_id: block.id,
        labels: {
          system_image_name: "tomcat-10"
        },
        skip_variant_setup: true
      )

      tomcat.image_variants.create!(
        label: "10",
        registry_image_tag: "10",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )

      tomcat.setting_params.create!(
        name: 'TOMCAT_PASSWORD',
        label: 'Tomcat PW',
        param_type: 'password'
      )
      tomcat.setting_params.create!(
        name: 'TOMCAT_USERNAME',
        label: 'Tomcat User',
        param_type: 'static',
        value: 'user'
      )
      tomcat.ingress_params.create!(
        port: 8080,
        proto: 'http',
        external_access: true
      )
      tomcat.env_params.create!(
        name: 'TOMCAT_PASSWORD',
        param_type: 'variable',
        env_value: 'build.settings.TOMCAT_PASSWORD'
      )
      tomcat.env_params.create!(
        name: 'TOMCAT_USERNAME',
        param_type: 'variable',
        env_value: 'build.settings.TOMCAT_USERNAME'
      )
      tomcat.env_params.create!(
        name: 'JAVA_OPTS',
        param_type: 'static',
        static_value: '-Djava.awt.headless=true -XX:+UseG1GC -Dfile.encoding=UTF-8 -Duser.home=$TOMCAT_HOME'
      )
      tomcat.env_params.create!(
        name: 'TOMCAT_ALLOW_REMOTE_MANAGEMENT',
        param_type: 'static',
        static_value: '0'
      )
      tomcat.volumes.create!(
        label:             'tomcat',
        mount_path:        '/bitnami/tomcat',
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
