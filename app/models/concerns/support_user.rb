module SupportUser
  extend ActiveSupport::Concern

  included do
    scope :support_admin, -> { where(email: 'hello@computestacks.com') }
  end

  def is_support_admin?
    %w(hello@computestacks.com kris@computestacks.com).include?(email)
  end

end