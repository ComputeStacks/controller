namespace :containers do
  desc "Install elasticsearch for wordpress"
  task wp_elasticsearch: :environment do
    ghprovider = ContainerImageProvider.find_by(name: "Github")
    es_lb      = ContainerImage.where("labels @> ?", { system_image_name: "es-loadbalancer-v1" }.to_json).first
    if es_lb.nil?
      es_lb = ContainerImage.create!(
        name:                     'es-nginx-lb',
        label:                    'ElasticSearch LoadBalancer',
        role:                     'loadbalancer',
        category: "other",
        is_load_balancer:         true,
        can_scale:                true,
        container_image_provider: ghprovider,
        registry_image_path:      "computestacks/es-nginx-lb",
        registry_image_tag:       "v1",
        is_free:                  true,
        labels:                   {
          system_image_name: "es-loadbalancer-v1"
        },
        skip_variant_setup: true
      )
      es_lb.image_variants.create!(
        label: "v1",
        is_default: true,
        registry_image_tag: "v1",
        version: 0,
        skip_tag_validation: true,
        validated_tag: true,
        validated_tag_updated: Time.now
      )
      es_lb.setting_params.create!(
        name:       'password',
        label:      'Password',
        param_type: 'password'
      )
      es_lb.env_params.create!(
        name:       'HTTPASS',
        param_type: 'variable',
        env_value:  'build.settings.password'
      )
      es_lb.ingress_params.create!(
        port:            80,
        external_access: true,
        proto:           'http'
      )
    end

    lb_rule = es_lb.ingress_params.first

    return false if lb_rule.nil?

    unless ContainerImage.where("labels @> ?", { system_image_name: "elasticsearch-6.4" }.to_json).exists?
      elasticsearch = ContainerImage.create!(
        name:                     'elasticsearch-64',
        label:                    "ElasticSearch for Wordpress",
        description:              "<div>ElasticSearch is a powerful search server. Add it to your site to improve speed and accuracy of your search results.</div>",
        role:                     'elasticsearch',
        category:               'other',
        can_scale:                false,
        container_image_provider: ghprovider,
        registry_image_path:      "computestacks/cs-docker-es-for-wp",
        registry_image_tag:       "6.4.3",
        min_cpu:                  1,
        min_memory:               1024,
        labels:                   {
          system_image_name: "elasticsearch-6.4"
        },
        skip_variant_setup: true
      )
      elasticsearch.image_variants.create!(
        label: "v6",
        is_default: true,
        version: 0,
        registry_image_tag: "v6",
        validated_tag: true,
        validated_tag_updated: Time.now,
        skip_tag_validation: true
      )
      elasticsearch.env_params.create!(
        name:       "cluster.name",
        label:      "Cluster Name",
        param_type: "variable",
        env_value:  "build.self.service_name"
      )
      elasticsearch.env_params.create!(
        name:         "discovery.type",
        label:        "Discovery Type",
        param_type:   "static",
        static_value: "single-node"
      )
      elasticsearch.env_params.create!(
        name:         "ES_JAVA_OPTS",
        label:        "ES_JAVA_OPTS",
        param_type:   "static",
        static_value: "-Xms416m -Xmx416m"
      )
      elasticsearch.env_params.create!(
        name:         "xpack.security.enabled",
        label:        "xpack",
        param_type:   "static",
        static_value: "false"
      )

      elasticsearch.ingress_params.create!(
        port:               9200,
        external_access:    true,
        proto:              'http',
        load_balancer_rule: lb_rule
      )
      elasticsearch.ingress_params.create!(
        port:            9300,
        external_access: false,
        proto:           'tcp'
      )
      elasticsearch.volumes.create!(
        label:             'esdata',
        mount_path:        "/usr/share/elasticsearch/data",
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
