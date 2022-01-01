#docker run --rm -d --name elasticsearch -p 9200:9200 -p 9300:9300 -e "discovery.type=single-node" docker.elastic.co/elasticsearch/elasticsearch:7.12.1

namespace :containers do

  namespace :elasticsearch do

    desc "Install elasticsearch 7"
    task v7: :environment do
      unless ContainerImage.where("labels @> ?", { system_image_name: "elasticsearch-7" }.to_json).exists?
        unless ContainerImageProvider.where(name: "Elastic").exists?
          puts "Creating Elastic Image Provider..."
          ContainerImageProvider.create!(
            name: "Elastic",
            is_default: false,
            hostname: "docker.elastic.co"
          )
        end
        cprovider = ContainerImageProvider.find_by(name: "Elastic")
        elasticsearch = ContainerImage.create!(
          name:                     'elasticsearch-7',
          label:                    'ElasticSearch 7',
          description:              "ElasticSearch is a powerful search server. Add it to your site to improve speed and accuracy of your search results.",
          role:                     'elasticsearch',
          role_class:               'misc',
          can_scale:                false,
          container_image_provider: cprovider,
          registry_image_path:      "elasticsearch/elasticsearch",
          registry_image_tag:       "7.12.1",
          min_cpu:                  1,
          min_memory:               1024,
          validated_tag: true,
          validated_tag_updated: Time.now,
          labels:                   {
            system_image_name: "elasticsearch-7"
          }
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
end
