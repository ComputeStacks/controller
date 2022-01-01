module NotifierServices
  class EmailNotifier

    attr_accessor :alert,
                  :event,
                  :email,
                  :subject,
                  :description,
                  :labels # [ { 'key' => '', 'value' => '' } ]

    def initialize(email)
      self.email = email
      self.alert = nil
      self.event = nil
      self.subject = nil
      self.description = nil
      self.labels = []
    end

    def perform
      if subject.nil? # Alert
        AlertMailer.alert_notification(alert, email).deliver_now
      else
        # App event

        l = labels.empty? ? [] : labels.select { |i| i['key'] != 'link' }
        link = labels.empty? ? nil : labels.select { |i| i['key'] == 'link' }[0]
        s = link.nil? ? subject : %Q( #{subject} (<a href="#{link['value']}">view</a>) )

        l = l.map { |i| [i['key'], i['value']] } # Mailer templates expect this in `[ [k,v] ]` format.

        AlertMailer.app_event_notification(s, description, email, l).deliver_now
      end
    rescue => e
      ExceptionAlertService.new(e, '320173a7d9dc7385').perform
      event.event_details.create!(
        data: "Fatal Error: #{e.message}",
        event_code: "0dcdb1f20db72a5c"
      ) if event
      false
    end

  end
end
