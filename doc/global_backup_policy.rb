##
# Example script to mass update all volumes and images to a single schedule.
# Run from `cstacks console`
ContainerImage::VolumeParam.where(borg_enabled: true).update_all borg_keep_hourly: 1, borg_keep_daily: 7, borg_keep_weekly: 4, borg_keep_monthly: 0, borg_keep_annually: 0

Volume.where(borg_enabled: true).update_all borg_keep_hourly: 1, borg_keep_daily: 7, borg_keep_weekly: 4, borg_keep_monthly: 0, borg_keep_annually: 0

Volume.where(borg_enabled: true).all.each do |vol|
  vol.update_consul!
end
