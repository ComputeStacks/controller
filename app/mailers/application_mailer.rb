class ApplicationMailer < ActionMailer::Base

  before_action :configure_smtp

  layout 'mailer'

  def default_url_options
    {
      host: Setting.hostname
    }
  end

  private

  def configure_smtp
    Setting.smtp_init!
    ActionMailer::Base.default_options = { from: Setting.smtp_from }
    ActionMailer::Base.smtp_settings = {
      address: Setting.find_by(name: 'smtp_server', category: 'mail').value,
      port: Setting.find_by(name: 'smtp_port', category: 'mail').value,
      user_name: Setting.find_by(name: 'smtp_username', category: 'mail').value,
      password: Setting.find_by(name: 'smtp_password', category: 'mail').decrypted_value
    }
  rescue => e
    ExceptionAlertService.new(e, 'ed62e8a43a809eba').perform
    {}
  end

end

