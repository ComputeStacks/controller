module Projects
  module ProjectLogs
    extend ActiveSupport::Concern

    def log_client
      region&.log_client
    end

    def logs(time_start, time_end, limit = 500)
      ff = Feature.find_by(name: 'loki_fluentd')
      ff = Feature.create!(name: 'loki_fluentd', maintenance: false, active: false) if ff.nil?
      loki_query = if ff.active
                     %Q({job="fluentd",project_id="#{id}"} | logfmt | line_format "{{.log}}")
                   else
                     %Q({project_id="#{id}"})
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

  end
end
