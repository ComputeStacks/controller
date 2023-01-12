##
# Process all non-prometheus events, as listed in SystemNotification
class ProcessAppEventWorker
  include Sidekiq::Worker

  def perform(alert_name, user_id, obj_id, data = {})

    obj = GlobalID::Locator.locate obj_id
    user = user_id.blank? ? nil : GlobalID::Locator.locate(user_id)

    SystemNotification.where( Arel.sql %Q('#{alert_name}' = ANY (rules)) ).each do |i|
      if data.empty?
        next if obj.nil?
        i.fire_app_alert! obj, alert_name
      else
        subject = data['subject']
        description = data['description']
        labels = data['labels'].nil? ? [] : data['labels']
        next if subject.blank? || description.blank?
        i.fire_app_alert_with_data!(subject, description, labels)
      end
    end

    # For non-admins, we _must_ have the user
    return if user.nil? || !user.is_a?(User)

    ProjectNotification.where( Arel.sql %Q(deployments.user_id = #{user.id} AND '#{alert_name}' = ANY (rules)) ).joins(:user).each do |i|
      if data.empty?
        next if obj.nil?
        i.fire_app_alert! obj, alert_name
      else
        subject = data['subject']
        description = data['description']
        labels = data['labels'].nil? ? [] : data['labels']
        next if subject.blank? || description.blank?
        i.fire_app_alert_with_data!(subject, description, labels)
      end
    end

    UserNotification.where( Arel.sql %Q('#{alert_name}' = ANY (rules)) ).where(user: user).each do |i|
      if data.empty?
        next if obj.nil?
        i.fire_app_alert! obj, alert_name
      else
        subject = data['subject']
        description = data['description']
        labels = data['labels'].nil? ? [] : data['labels']
        next if subject.blank? || description.blank?
        i.fire_app_alert_with_data!(subject, description, labels)
      end
    end
  rescue ActiveRecord::RecordNotFound
    return
  rescue => e
    ExceptionAlertService.new(e, '02165035182a4b82').perform
  end

end
