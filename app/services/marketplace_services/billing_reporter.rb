module MarketplaceServices
  ##
  # Report usage of items that we need to bill for.
  class BillingReporter

    METRICS_CACHE_KEY = "marketplace_report_metrics"
    USAGE_CACHE_KEY = "marketplace_report_usage"

    attr_accessor :errors

    def initialize
      self.errors = []
    end

    # @return [Boolean]
    def perform
      # Skip If we're not configured
      if Setting.marketplace_username.blank? || Setting.marketplace_password.blank?
        errors << "Missing marketplace credentials, skipping..."
        return false
      end

      # Skip If it's not due
      unless send_heartbeat? || send_usage?
        errors << "Nothing to report, skipping..."
        return false
      end

      # Skip If we can't connect
      return false unless ingress_connection.is_a?(PG::Connection)

      # Send Heartbeat
      if send_heartbeat?
        if report_heartbeat!
          Rails.cache.write(METRICS_CACHE_KEY, Time.now.to_i)
        end
      end

      ContainerImagePlugin.all.each do |plugin|
        next unless plugin.marketplace_billable?
        case plugin.marketplace_billable_group
        when :service, :container
          plugin.service_plugins.each do |service_plugin|
            report_usage! plugin, service_plugin
          end
        when :aggregate
          # not implemented
          next
        else
          next
        end
      end
      if errors.empty?
        Rails.cache.write(USAGE_CACHE_KEY, Time.now.to_i)
      end
      errors.empty?
    end

    def report_usage!(image_plugin, service_plugin)
      service = service_plugin.container_service
      if service.nil?
        errors << "Unknown service"
        return false
      end
      data = image_plugin.marketplace_usage_report service_plugin
      if data.empty?
        errors << "No data to report"
        return false
      end
      return false unless ingress_connection.is_a?(PG::Connection)
      fields = data[:fields]
      fields = %w(username controller_ip hostname) + fields
      value_count = []
      1.upto(fields.count) do |i|
        value_count << "$#{i}"
      end
      insert_statement = %Q(INSERT INTO #{data[:table]} (#{fields.join(',')}) values (#{value_count.join(',')}))
      insert_values = data[:values]
      insert_values = [Setting.marketplace_username, controller_ip, Setting.hostname] + insert_values
      result = ingress_connection.exec_params insert_statement, insert_values
      valid_result? result
    end

    def report_heartbeat!
      return false unless ingress_connection.is_a?(PG::Connection)
      result = ingress_connection.exec_params "INSERT INTO v1.metrics (username,app_name,company_name,controller_ip,hostname,users,containers,projects,nodes,regions,locations) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
                                     [
                                       Setting.marketplace_username,
                                       Setting.app_name,
                                       Setting.company_name,
                                       controller_ip,
                                       Setting.hostname,
                                       User.count,
                                       Deployment::Container.count,
                                       Deployment.count,
                                       Node.count,
                                       Region.count,
                                       Location.count
                                     ]
      valid_result? result
    rescue => e
      ExceptionAlertService.new(e, '2778bf93a28c1c70').perform
      errors << e.message
      false
    end

    #private

    # Parse the response of the result
    # @param [PG::Result] result
    # @return [Boolean]
    def valid_result?(result)
      # result.check will raise an exception If there is an error with the query
      if result.is_a?(PG::Result) && result.check.is_a?(PG::Result)
        return true
      elsif result.is_a?(PG::Result)
        errors << result.result_error_message
      else
        errors << "Fatal error"
      end
      false
    end

    # Send metrics daily
    def send_heartbeat?
      last_attempt = Rails.cache.read METRICS_CACHE_KEY
      return true if last_attempt.nil?
      return false if Time.at(last_attempt) > 1.day.ago.to_time
      true
    rescue => e
      ExceptionAlertService.new(e, 'c50ba5909d9984e2').perform
      errors << e.message
      true
    end

    # Send usage hourly
    def send_usage?
      last_attempt = Rails.cache.read USAGE_CACHE_KEY
      return true if last_attempt.nil?
      return false if Time.at(last_attempt) > 1.hour.ago.to_time
      true
    rescue => e
      ExceptionAlertService.new(e, 'a851b169e2f2b052').perform
      errors << e.message
      true
    end

    # Determine our IP for reporting usage metrics
    def controller_ip
      ip = Rails.cache.fetch("controller_ip", expires_in: 1.hour, skip_nul: true) do
        begin
          dns = Dnsruby::Resolver.new({ port: NS_PORT, nameserver: %w(ns1.google.com ns2.google.com ns3.google.com ns4.google.com) })
          dns.retry_delay = 1
          dns.retry_times = 3
          dns.query("o-o.myaddr.l.google.com", "TXT").answer.first.strings.first
        rescue => e
          ExceptionAlertService.new(e, '9f322b258ea48956').perform
          errors << e.message
          nil
        end
      end
      ip.nil? ? "127.0.0.1" : ip
    end

    def ingress_connection
      return nil if Setting.marketplace_username.blank?
      return nil if Setting.marketplace_password.blank?
      marketplace_endpoint = if Rails.env.production?
                               "ingress.marketplace.cmptstks.com/ingress?sslmode=require"
                             else
                               ENV['INGRESS_TEST_URI']
                             end
      uri = "postgresql://#{Setting.marketplace_username}:#{Setting.marketplace_password}@#{marketplace_endpoint}"
      if PG::Connection.ping(uri) > 0
        errors << "Unable to connect to ingress endpoint"
        return nil
      end
      PG.connect uri
    rescue => e
      ExceptionAlertService.new(e, '4e73ca53698c059d').perform
      errors << e.message
      nil
    end

  end
end
