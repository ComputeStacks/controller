module SystemEventsHelper

  def sys_event_label(log)
    case log.log_level
    when 'debug'
      'label-primary'
    when 'info'
      'label-info'
    when 'warn'
      'label-danger'
    end
  end

end