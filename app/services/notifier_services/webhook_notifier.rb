##
# Process WebHook Notifications
#
# Currently in use by:
# * Google Chat
# * MS Teams
# * Generic WebHook
module NotifierServices
  class WebhookNotifier

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
      data = { text: (subject.nil? ? alert_msg : app_event_msg) }.to_json
      WebHookService.new(nil, data, webhook_url).perform
    rescue => e
      ExceptionAlertService.new(e, '20502fa52261d51d').perform
      event.event_details.create!(
        data: "Fatal Error: #{e.message}",
        event_code: "9a7201b68dacd930"
      ) if event
      false
    end

    private

    def alert_msg
      public_url = alert.public_url
      message = public_url ? "*#{alert.description}*\n<#{public_url}|View Alert>" : alert.description

      if alert.container
        c = alert.container
        s = c.service
        message = %Q(#{message}\n*Container:* #{c.name})
        message = %Q(#{message}\n*Service:* #{s.label})
        message = %Q(#{message}\n*Primary Domain:* #{s.master_domain.domain}) if s.master_domain
      end
      message = %Q(#{message}\n*SFTP Container:* #{alert.sftp_container.name}) if alert.sftp_container
      message = %Q(#{message}\n*Node:* #{alert.node.label}) if alert.node
      alert.labels.each do |k, v|
        message = %Q(#{message}\n*#{k}:* `#{v}`)
      end
      message
    end

    def app_event_msg
      l = labels.empty? ? [] : labels.select { |i| i['key'] != 'link' }
      link = labels.empty? ? nil : labels.select { |i| i['key'] == 'link' }[0]
      s = link.nil? ? subject : %Q( *#{subject}* (<#{link['value']}|view>) )

      d = description
      l.each do |i|
        d = %Q( #{d}\n*#{i['key']}:* `#{i['value']}` )
      end

      %Q(#{s}\n#{d})
    end

  end
end
