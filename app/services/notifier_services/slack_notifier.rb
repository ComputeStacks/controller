module NotifierServices
  class SlackNotifier

    attr_accessor :alert,
                  :webhook_url,
                  :event,
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
      data = (subject.nil? ? alert_msg : app_event_msg).to_json
      WebHookService.new(nil, data, webhook_url).perform
    rescue => e
      ExceptionAlertService.new(e, 'ac098afdf7b6c731').perform
      event.event_details.create!(
        data: "Fatal Error: #{e.message}",
        event_code: "729c90b897ec7a84"
      ) if event
      false
    end

    private

    def app_event_msg
      l = labels.empty? ? [] : labels.select { |i| i['key'] != 'link' }
      link = labels.empty? ? nil : labels.select { |i| i['key'] == 'link' }[0]
      s = link.nil? ? subject : %Q( #{subject} (<#{link['value']}|view>) )
      data = {
        text: subject,
        blocks: [
          {
            type: 'section',
            text: {
              type: 'mrkdwn', # no, this is not misspelled.
              text: s
            }
          }
        ]
      }

      unless l.empty?
        fields = []
        l.each do |i|
          fields << {
            type: 'mrkdwn',
            text: %Q( *#{i['key']}*: `#{i['value']}` )
          }
        end
        data[:blocks] << {
          type: 'section',
          fields: fields
        } unless fields.empty?
      end

      data
    end

    def alert_msg
      public_url = alert.public_url
      message = public_url ? "*#{alert.description}*\n<#{public_url}|View Alert>" : alert.description
      data = {
        text: alert.description,
        blocks: [
          {
            type: 'section',
            text: {
              type: 'mrkdwn', # no, this is not misspelled.
              text: message
            }
          }
        ]
      }
      fields = []
      if alert.container
        c = alert.container
        s = c.service
        fields << {
          type: 'mrkdwn',
          text: "*Container:*\n#{c.name}"
        }
        fields << {
          type: 'mrkdwn',
          text: "*Service:*\n#{s.label}"
        }
        fields << {
          type: 'mrkdwn',
          text: "*Primary Domain:*\n#{s.master_domain.domain}"
        } if s.master_domain
      end
      if alert.sftp_container
        fields << {
          type: 'mrkdwn',
          text: "*SFTP Container:*\n#{alert.sftp_container.name}"
        }
      end
      if alert.node
        fields << {
          type: 'mrkdwn',
          text: "*Node:*\n#{alert.node.label}"
        }
      end
      alert.labels.each do |k, v|
        fields << {
          type: 'mrkdwn',
          text: "*#{k}:*\n#{v}"
        }
      end
      data[:blocks] << {
        type: 'section',
        fields: fields
      } unless fields.empty?
      data
    end

  end
end
