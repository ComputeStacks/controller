module ContainerServices
  module ServicePlugins
    # Monarx Integration for a given Container Service
    module MonarxServicePlugin
      extend ActiveSupport::Concern

      included do

        scope :monarx, -> { where("container_image_plugins.name = 'monarx'").joins(:container_image_plugin) }

      end

      # @return [Boolean]
      def monarx_available?
        return false unless active
        return false unless container_image_plugin.name == "monarx"
        container_image_plugin.monarx_available?
      end

      # @return [Hash]
      def monarx_config(c = {})
        return c unless monarx_available?
        (c['Env'] ||= []) << "MONARX_ID=#{Setting.monarx_agent_key}"
        c['Env'] << "MONARX_SECRET=#{Setting.monarx_agent_secret}"
        c['Env'] << "MONARX_AGENT=#{container_service.name}"
        c
      end

      def monarx_plugin_url
        Rails.cache.fetch("monarx_url_#{name}", expires_in: 2.hours, skip_nil: true) do
          return nil if monarx_agent_id.nil?
          data = {
            enterprise_id: Setting.monarx_enterprise_id,
            agent_id: monarx_agent_id,
            home_dir: "/var/www"
          }
          result = HTTP.timeout(30)
                       .headers(container_image_plugin.monarx_api_headers)
                       .post "#{container_image_plugin.monarx_base_url}/auth/plugin/link", json: data
          if result.status.success?
            begin
              response = Oj.load result.body.to_s
            rescue
              return nil
            end
            response['url'].blank? ? nil : response['url']
          else
            nil
          end
        end
      end

      def monarx_agent_id
        Rails.cache.fetch("monarx_agentid_#{name}", expires_in: 1.week, skip_nil: true) do

          result = HTTP.timeout(30)
                       .headers(container_image_plugin.monarx_api_headers)
                       .get "#{container_image_plugin.monarx_enterprise_url}/agent", params: { filter: "agent.tags==#{name}" }

          if result.status.success?
            begin
              response = Oj.load result.body.to_s
            rescue
              return nil
            end
            return nil if response.dig("_embedded", "items").nil?
            return nil if response["_embedded"]["items"].empty?
            active_container_names = containers.pluck(:name)
            mid = nil
            response["_embedded"]["items"].each do |i|
              if active_container_names.include?(i['host_id'])
                mid = i['id']
                break
              end
            end
            mid
          else
            nil
          end
        end
      end

      def monarx_stats
        Rails.cache.fetch("monarx_stats_#{name}", expires_in: 4.hours, skip_nul: true) do
          return nil if monarx_agent_id.nil?
          result = HTTP.timeout(30)
                       .headers(container_image_plugin.monarx_api_headers)
                       .get "#{container_image_plugin.monarx_enterprise_url}/agent-file/metrics/agent-file-agent-classification", params: { filter: "agent_id==#{monarx_agent_id}"}
          if result.status.success?
            begin
              response = Oj.load result.body.to_s
            rescue
              return nil
            end
            return nil if response.empty?
            return nil if response[0]['counts'].nil?
            response[0]
          else
            nil
          end
        end
      end

    end
  end
end
