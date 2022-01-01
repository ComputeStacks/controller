##
# Process Matrix Notifications
#
module NotifierServices
  class MatrixNotifier

    attr_accessor :alert,
                  :event,
                  :webhook_url,
                  :subject,
                  :description,
                  :labels # [ { 'key' => '', 'value' => '' } ]

    def initialize(webhook_url)
      self.webhook_url = webhook_url
      self.alert = nil
      self.subject = nil
      self.event = nil
      self.description = nil
      self.labels = []
    end

    def perform
      data = {
        text: (subject.nil? ? alert_msg : app_event_msg),
        format: "html",
        "displayName": Setting.app_name,
        "avatarUrl": "http://cdn.computestacks.net/icon.png"
      }.to_json
      WebHookService.new(nil, data, webhook_url).perform
    rescue => e
      ExceptionAlertService.new(e, '3498a3f24fd28e62').perform
      event.event_details.create!(
        data: "Fatal Error: #{e.message}",
        event_code: "3498a3f24fd28e62"
      ) if event
      false
    end

    private
    #
    # def format_description(desc)
    #   desc.gsub("*", "")
    # end

    def alert_msg
      public_url = alert.public_url
      message = public_url ? %Q(<b><a href="#{public_url}">#{alert.description}</a></b>) : "<b>#{alert.description}</b>"

      unless alert.labels.empty? && alert.container.nil?
        message = "#{message}<ul>"
        if alert.container
          c = alert.container
          s = c.service
          message = %Q(#{message}<li><b>Container:</b> #{c.name}</li>)
          message = %Q(#{message}<li><b>Service:</b> #{s.label}</li>)
          message = %Q(#{message}<li><b>Primary Domain:</b> #{s.master_domain.domain}</li>) if s.master_domain
        end
        message = %Q(#{message}<li><b>SFTP Container:</b> #{alert.sftp_container.name}</li>) if alert.sftp_container
        message = %Q(#{message}<li><b>Node:</b> #{alert.node.label}</li>) if alert.node
        alert.labels.each do |k, v|
          message = %Q(#{message}<li><b>#{k}:</b> <code>#{v}</code></li>)
        end
        message = "#{message}</ul>"
      end
      message
    end

    def app_event_msg
      l = labels.empty? ? [] : labels.select { |i| i['key'] != 'link' }
      link = labels.empty? ? nil : labels.select { |i| i['key'] == 'link' }[0]
      s = link.nil? ? subject : %Q(<a href="#{link['value']}">#{subject}</a>)

      d = description
      unless l.empty?
        d = "#{d}<ul>"
        l.each do |i|
          d = %Q(#{d}<li><b>#{i['key']}:</b> <code>#{i['value']}</code></li>)
        end
        d = "#{d}</ul>"
      end

      %Q(<b>#{s}</b><br>#{d})
    end

  end
end
