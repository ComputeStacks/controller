module ContainerServicePlugins
  module Monarx
    extend ActiveSupport::Concern


    def monarx_available?
      return false if monarx_plugin.nil?
      monarx_plugin.monarx_available?
    end

    def monarx_plugin
      container_image.container_image_plugins.active.monarx.first
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
                     .headers(monarx_plugin.monarx_api_headers)
                     .post "#{monarx_plugin.monarx_base_url}/auth/plugin/link", json: data
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
                     .headers(monarx_plugin.monarx_api_headers)
                     .get "#{monarx_plugin.monarx_enterprise_url}/agent", params: { filter: "agent.tags==#{name}" }

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
                     .headers(monarx_plugin.monarx_api_headers)
                     .get "#{monarx_plugin.monarx_enterprise_url}/agent-file/metrics/agent-file-agent-classification", params: { filter: "agent_id==#{monarx_agent_id}"}
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
