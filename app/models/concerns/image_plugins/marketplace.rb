module ImagePlugins
  ##
  # Basic settings for a plugin in our marketplace
  module Marketplace
    extend ActiveSupport::Concern

    # @return [Boolean]
    def marketplace_billable?
      marketplace_enabled_services.include? name
    end

    # @return [Symbol] :container, :service, :aggregate
    def marketplace_billable_group
      case name
      when 'demo', 'another_demo', 'required_demo'
        :container
      else
        :service
      end
    end

    # @return [Symbol] :month, :day, :hour
    def marketplace_minimum_rate
      :month # :day, :hour, etc.
    end

    # @param [Deployment::ContainerService::ServicePlugin] service_plugin
    # @return [Hash]
    def marketplace_usage_report(service_plugin)
      case name
      when 'monarx'
        marketplace_usage_for_monarx service_plugin
      when 'demo', 'another_demo', 'required_demo'
        marketplace_usage_for_demo service_plugin
      else
        {}
      end
    end

    # @return [Array]
    def marketplace_enabled_services
      if Rails.env.production?
        %w(monarx)
      else
        %w(monarx demo another_demo required_demo)
      end
    end

  end
end
