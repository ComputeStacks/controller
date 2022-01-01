# @!attribute current_user
#   @return [User]
# @!attribute current_audit
#   @return [Audit]
module Auditable
  extend ActiveSupport::Concern

  included do

    after_update :log_update_event
    after_create :log_create_event
    before_destroy :log_destroy_event, prepend: true

    attr_accessor :current_user, :current_audit, :current_event

  end

  # Who is performing his action?
  def user_performer
    if current_user
      current_user
    elsif current_audit
      current_audit.user
    elsif current_event
      current_event.audit&.user
    else
      nil
    end
  end

  private

  def log_update_event
    self.current_audit = Audit.create!(
      user: current_user,
      ip_addr: current_user.last_request_ip,
      event: 'updated',
      rel_id: self.id,
      rel_model: self.class.name
    ) if current_user && !current_audit
  end

  def log_create_event
    self.current_audit = Audit.create!(
      user: current_user,
      ip_addr: current_user.last_request_ip,
      event: 'created',
      rel_id: self.id,
      rel_model: self.class.name
    ) if current_user && !current_audit
  end

  def log_destroy_event
    self.current_audit = Audit.create!(
      user: current_user,
      ip_addr: current_user.last_request_ip,
      event: 'deleted',
      rel_model: self.class.name,
      raw_data: self.serializable_hash
    ) if current_user && !current_audit
  end

end
