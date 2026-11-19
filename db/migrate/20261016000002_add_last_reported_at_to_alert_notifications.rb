class AddLastReportedAtToAlertNotifications < ActiveRecord::Migration[7.2]
  # When Alertmanager last reported a firing alert. Alertmanager re-sends firing alerts
  # every repeat_interval, so a firing alert that stops being reported has lost its
  # resolve notification; AlertWorkers::ResolveStaleWorker resolves it.
  #
  # Firing alerts start the clock at upgrade time: a genuinely firing one is re-reported
  # within the hour, so the sweep resolves only those that never are. Without this, the
  # sweep could resolve live alerts before their next report and re-notify on it.
  def up
    add_column :alert_notifications, :last_reported_at, :datetime
    execute "UPDATE alert_notifications SET last_reported_at = NOW() WHERE status = 'firing'"
  end

  def down
    remove_column :alert_notifications, :last_reported_at
  end
end
