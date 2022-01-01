module Containers
  module ContainerLogs
    extend ActiveSupport::Concern

    def logs(time_start, time_end, limit = 500)
      ff = Feature.find_by(name: 'loki_fluentd')
      ff = Feature.create!(name: 'loki_fluentd', maintenance: false, active: false) if ff.nil?
      loki_query = if ff.active
                     %Q({job="fluentd",container_name="/#{name}"} | logfmt | line_format "{{.log}}")
                   else
                     %Q({container_name="#{name}"})
                   end
      log_client.query(
        query: loki_query,
        start: time_start.to_i,
        end: time_end.to_i,
        limit: limit
      )
    rescue
      []
    end

    # Format logs in an array for legacy use cases.
    def logs_array(oldest_first, limit)
      result = logs(2.days.ago, Time.now, limit).map { |i| i[2] }
      oldest_first ? result.reverse : reverse
    end

  end
end
