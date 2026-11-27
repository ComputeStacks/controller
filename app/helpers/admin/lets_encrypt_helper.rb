module Admin::LetsEncryptHelper
  def admin_lets_encrypt_path(lets_encrypt)
    "/admin/lets_encrypt/#{lets_encrypt.id}"
  end

  # Certificate column for the load balancer list: expiry, plus the renewal
  # backoff when recent attempts failed.
  def admin_lb_certificate_status(lb)
    return tag.span("-", class: "text-muted") unless lb.le
    cert = lb.lets_encrypt
    if cert.nil? || cert.expires_at.nil?
      status = tag.span("Not issued", class: "label label-warning")
    else
      days = ((cert.expires_at - Time.now) / 1.day).ceil
      css = if days < 14
        "label-danger"
      else
        (days < 30) ? "label-warning" : "label-success"
      end
      text = (cert.expires_at <= Time.now) ? "Expired" : "#{days}d left"
      status = link_to(tag.span(text, class: "label #{css}", title: "Expires #{l cert.expires_at, format: :short}"), admin_lets_encrypt_path(cert))
    end
    return status if cert.nil?
    safe_join([status, admin_lets_encrypt_backoff(cert, short: true)].compact, tag.br)
  end

  # Renewal backoff for a certificate, or nil when the last attempt succeeded.
  def admin_lets_encrypt_backoff(cert, short: false)
    return nil unless cert.failure_count.to_i > 0
    retry_text = if cert.next_attempt_at.nil? || cert.next_attempt_at <= Time.now
      "retry due now"
    else
      "retry in #{distance_of_time_in_words(Time.now, cert.next_attempt_at)}"
    end
    failures = pluralize(cert.failure_count, "failed attempt")
    if short
      tag.small("#{failures}, #{retry_text}", class: "text-danger", title: (cert.next_attempt_at && "Next attempt #{l cert.next_attempt_at, format: :short}"))
    else
      "#{failures} in a row, #{retry_text}" + (cert.next_attempt_at ? " (#{l cert.next_attempt_at, format: :short})" : "")
    end
  end

  def admin_lets_encrypt_auth_path(lets_encrypt_auth)
    "/admin/lets_encrypt/#{lets_encrypt_auth.certificate.id}/lets_encrypt_auth/#{lets_encrypt_auth.id}"
  end
end
