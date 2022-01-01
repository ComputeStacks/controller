module Deployments::CertificatesHelper

  def certificate_path(certificate)
    return "" if certificate.deployment.nil?
    "/deployments/#{certificate.deployment.token}/certificates/#{certificate.id}"
  end

  def edit_certificate_path(certificate)
    "#{certificate_path(certificate)}/edit"
  end

end