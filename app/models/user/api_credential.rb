##
# User API Credentials
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute username
#   @return [String]
#
# @!attribute password
#   @return [String]
#
# @!attribute user
#   @return [User]
#
class User::ApiCredential < ApplicationRecord

  include Auditable
  belongs_to :user

  before_create :generate_credentials!

  attr_accessor :generated_password # Only visible when created.

  def find_by_username(u)
    where(username: u, users: { active: true }).joins(:user).first
  end

  def valid_password?(pw)
    return false if password.blank?
    return false if user.access_locked?
    if user.failed_attempts >= Devise.maximum_attempts
      user.lock_access!
      return false
    end
    if BCrypt::Password.new(password) == pw
      user.unlock_access! unless user.failed_attempts.zero?
      true
    else
      user.increment_failed_attempts
      false
    end
  rescue => e
    ExceptionAlertService.new(e, '9fb6e21854ad8d6e').perform
    return false
  end

  private

  def generate_credentials!
    if password.blank?
      self.generated_password = SecureRandom.base64(30)
      self.password = BCrypt::Password.create(generated_password)
    end
    self.username = SecureRandom.urlsafe_base64(14) if username.blank?
  end

end
