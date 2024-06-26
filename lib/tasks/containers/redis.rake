namespace :containers do

  desc "Install redis container"
  task redis: :environment do
    if ContainerImage.find_by(name: 'redis').nil?

      # Setup block
      block = Block.create!(title: 'Redis Remote Access', content_key: 'redis_remote')
      block.block_contents.create!(
        locale: ENV['LOCALE'],
        body:   "<h4>External Access</h4><div><br></div><div>This redis service uses TLS encryption when connecting from <em>outside</em> your project. To access your service, your redis client will need to support this.<br><br>Here is your endpoint:</div><div>{% for ingress in ingress_rules %}<strong>tls://{{ default_domain}}:{{ingress.port_nat}}</strong><br>{% endfor %}<br>Connecting locally from within your project just requires the individual local ip address of your container:<br>{% for container in containers %}redis://{{container.ip}}:6379<br>{% endfor %}</div>"
      )

      dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
      redis      = ContainerImage.create!(
        label:                    'Redis',
        name:                     'redis',
        description:              'Redis in-memory key/value store. This image does not save data to disk.',
        role:                     'redis',
        category:               'cache',
        can_scale:                false,
        is_free:                  false,
        container_image_provider: dhprovider,
        registry_image_path:      "redis",
        remote_block_id:          block.id,
        command:                  "/bin/sh -c redis-server --save "" --appendonly no",
        labels:                   {
          system_image_name: "redis-public"
        },
        skip_variant_setup: true
      )
      redis.image_variants.create!(
        label: "7.2",
        registry_image_tag: "7.2-alpine",
        validated_tag: true,
        validated_tag_updated: Time.now,
        version: 0,
        is_default: true,
        skip_tag_validation: true
      )
      redis.ingress_params.create!(
        port:            6379,
        proto:           'tcp',
        external_access: false
      )
      redis.volumes.create!(
        label:             'redis',
        mount_path:        '/data',
        enable_sftp:       false,
        borg_enabled:      false
      )
    end
  end

end
