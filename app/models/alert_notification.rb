##
# Alert Notification
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute name
#   @return [String]
#
# @!attribute fingerprint
#   @return [String]
#
# @!attribute status
#   @return [firing,completed]
#
# @!attribute severity
#   @return [String]
#
# @!attribute service
#   @return [String] Not the container service name, but the service on the node.
#
# @!attribute container
#   @return [Deployment::Container]
#
# @!attribute sftp_container
#   @return [Deployment::Sftp]
#
# @!attribute description
#   @return [String]
#
# @!attribute value
#   @return [Decimal]
#
# @!attribute labels
#   @return [Hash]
#
# @!attribute event_count
#   @return [Integer] The number of times this alert has been triggered
#
# @!attribute last_event
#   @return [DateTime]
#
class AlertNotification < ApplicationRecord

  include Authorization::Alert

  scope :sorted, -> { order created_at: :desc }
  scope :active, -> { where status: 'firing' }
  scope :resolved, -> { where status: 'resolved' }
  scope :recent, -> { where Arel.sql %Q( alert_notifications.updated_at > '#{1.month.ago.iso8601}' ) }
  scope :admin_only, -> { where Arel.sql(%Q(name != 'ContainerMemoryUsage' AND name != 'ContainerCpuUsage')) }

  belongs_to :container,
             class_name: 'Deployment::Container',
             foreign_key: 'container_id',
             optional: true

  belongs_to :sftp_container,
             class_name: 'Deployment::Sftp',
             foreign_key: 'sftp_container_id',
             optional: true

  belongs_to :node, optional: true

  has_and_belongs_to_many :event_logs

  attr_accessor :resolve

  before_validation :set_status

  # @!group States

  # @return [Boolean]
  def active?
    status == 'firing'
  end

  # @return [Boolean]
  def resolved?
    status == 'resolved'
  end

  # @!endgroup

  # Do we have notifications that will get sent out?
  # @return [Boolean]
  def has_notifications?
    ProjectNotification.where( Arel.sql %Q('#{name}' = ANY (rules)) ).exists? || UserNotification.where( Arel.sql %Q('#{name}' = ANY (rules)) ).exists? ||SystemNotification.where( Arel.sql %Q('#{name}' = ANY (rules)) ).exists?
  end

  # @return [String]
  def public_url
    "#{PORTAL_HTTP_SCHEME}://#{Setting.hostname}/alert_notifications/#{id}"
  end

  private

  def set_status
    self.status = 'resolved' if resolve
  end

end
