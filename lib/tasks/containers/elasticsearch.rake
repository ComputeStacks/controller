#docker run --rm -d --name elasticsearch -p 9200:9200 -p 9300:9300 -e "discovery.type=single-node" docker.elastic.co/elasticsearch/elasticsearch:7.12.1

namespace :containers do
  desc "Install elasticsearch"
  task elasticsearch: :environment do
      unless ContainerImage.where(name: "elasticsearch").exists?
        dhprovider = ContainerImageProvider.find_by(name: "DockerHub")
        elasticsearch = ContainerImage.create!(
          name:                     'elasticsearch',
          label:                    'ElasticSearch',
          description:              "ElasticSearch is a powerful search server. Add it to your site to improve speed and accuracy of your search results.",
          role:                     'elasticsearch',
          category:               'misc',
          can_scale:                false,
          container_image_provider: dhprovider,
          registry_image_path:      "elasticsearch",
          min_cpu:                  1,
          min_memory:               1024
        )
        elasticsearch.image_variants.create!(
          label: "8.4.3",
          registry_image_tag: "8.4.3",
          validated_tag: true,
          validated_tag_updated: Time.now,
          version: 0,
          is_default: true,
          skip_tag_validation: true
        )
        elasticsearch.image_variants.create!(
          label: "7.17.6",
          registry_image_tag: "7.17.6",
          validated_tag: true,
          validated_tag_updated: Time.now,
          version: 1,
          skip_tag_validation: true
        )
        elasticsearch.image_variants.create!(
          label: "6.8.23",
          registry_image_tag: "6.8.23",
          validated_tag: true,
          validated_tag_updated: Time.now,
          version: 2,
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

        elasticsearch.ingress_params.create!(
          port:               9200,
          external_access:    false,
          proto:              'http'
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
