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

end