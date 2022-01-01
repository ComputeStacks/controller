module Collaborations
  extend ActiveSupport::Concern

  included do

    scope :sorted, -> { order("lower(users.lname)").joins(:collaborator) }
    scope :active, -> { where(active: true) }

    # Add user by email
    attr_accessor :user_email

    # Allow admins to skip confirmation
    attr_accessor :skip_confirmation

    before_validation :set_user_by_email

    before_save :set_active

    before_create :user_can_perform?
    before_destroy :user_can_perform?

    validate :ensure_active_user
    validate :ensure_not_owner

  end

  class_methods do

    def find_all_for_user(current_user)
      return where("2 = 3") if current_user.nil?
      where user_id: current_user.id
    end

    def find_for_user(current_user, arg, *args)
      return nil if current_user.nil?
      resource = find_by arg, args
      return nil if resource.nil?
      resource
    end

  end

  def is_resource_owner?(current_user)
    return false if resource_owner.nil?
    resource_owner == current_user
  end

  def can_administer?(current_user)
    current_user.is_admin || is_resource_owner?(current_user) || collaborator == current_user
  end

  def url_path(current_user)
    return nil unless current_user.is_admin
    return nil if collaborator.nil?
    "/admin/users/#{collaborator.id}"
  end

  private

  def set_active
    return unless ActiveRecord::Type::Boolean.new.cast(skip_confirmation)
    self.active = true
  end

  def set_user_by_email
    return if user_email.blank? || !collaborator.nil?
    self.collaborator = User.find_by email: user_email
  end

  def ensure_active_user
    return if collaborator.nil?
    errors.add(:collaborator, 'exists, but has not confirmed their account.') unless collaborator.confirmed?
    errors.add(:collaborator, 'exists, but is currently suspended.') unless collaborator.active
  end

  def user_can_perform?
    if current_user.nil?
      errors.add(:base, 'missing current_user, permission denied')
      throw :abort
    else
      return if can_administer?(current_user)
      errors.add(:base, 'permission denied')
      throw :abort
    end
  end

  def ensure_not_owner
    return if resource_owner.nil? || collaborator.nil?
    errors.add(:collaborator, 'is the resource owner') if resource_owner == collaborator
  end

end
