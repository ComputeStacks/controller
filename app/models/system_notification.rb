##
# SystemNotification manages alerts based on system alerts
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute label
#   @return [String]
#
# @!attribute notifier
#   @return [email,keybase,matrix,slack,webhook,gchat]
#
# @!attribute value
#   Endpoint for notifier selected.
#   @return [String]
#
# @!attribute rules
#   @return [Array]
#
class SystemNotification < ApplicationRecord

  include Auditable
  include Notifications::Common

  ##
  # Disabled
  #
  # * AlertmanagerConfigurationReload
  # * PrometheusConfigurationReload
  # * PrometheusNotConnectedToAlertmanager
  def self.prometheus_alerts
    %w(
      DiskWillFillIn4Hours
      ExporterDown
      HighCpuLoad
      NodeUp
      OutOfDiskSpace
      OutOfInodes
      OutOfMemory
      UnusualDiskReadLatency
      UnusualDiskWriteLatency
    )
  end

  def self.app_event_alerts
    %w(
      ContainerBootFailed
      NewOrder
      UserActivated
      UserCreated
      UserDeleted
      UserSuspended
    )
  end

end
