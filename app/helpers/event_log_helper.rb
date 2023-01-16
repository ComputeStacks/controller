module EventLogHelper

  def log_reason_class(log)
    case log.status
    when 'completed'
      'alert-success'
    when 'failed'
      'alert-danger'
    else
      'alert-info'
    end
  end

  def event_status_panel_header_color(event)
    case event.status
    when 'running'
      'panel-primary'
    when 'completed'
      'panel-success'
    when 'failed'
      'panel-danger'
    else # 'pending', 'cancelled'
      'panel-default'
    end
  end

end
