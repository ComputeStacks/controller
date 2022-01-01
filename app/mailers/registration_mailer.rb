##
# Mailer in use by Devise for:
#   - Confirmation
#   - Password Reset
#   - Unlock your account
#
# Templates pulled from: https://github.com/wildbit/postmark-templates
#
class RegistrationMailer < Devise::Mailer

  helper :application
  include Devise::Controllers::UrlHelpers
  default template_path: 'devise/mailer'

  before_action :configure_smtp

  def confirmation_instructions(record, token, opts={})
    set_locale(record)
    block_content = Block.find_by(content_key: 'email.confirmation').block_contents.find_by(locale: I18n.locale)
    block_content = Block.find_by(content_key: 'email.confirmation').block_contents.find_by(locale: I18n.default_locale) if block_content.nil?
    @email_content = block_content.body
    super
  end

  def reset_password_instructions(record, token, opts={})
    set_locale(record)
    block_content = Block.find_by(content_key: 'email.password').block_contents.find_by(locale: I18n.locale)
    block_content = Block.find_by(content_key: 'email.password').block_contents.find_by(locale: I18n.default_locale) if block_content.nil?
    @email_content = block_content.body
    super
  end

  def unlock_instructions(record, token, opts={})
    set_locale(record)
    block_content = Block.find_by(content_key: 'email.unlock').block_contents.find_by(locale: I18n.locale)
    block_content = Block.find_by(content_key: 'email.unlock').block_contents.find_by(locale: I18n.default_locale) if block_content.nil?
    @email_content = block_content.body
    super
  end

  def default_url_options
    {
      host: Setting.hostname
    }
  end

  private

  def set_locale(user)
    I18n.locale = user.locale || I18n.default_locale
  end

  def configure_smtp
    Setting.smtp_init!
    Devise.mailer_sender = Setting.smtp_from
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
