attributes :id, :csrn, :name, :label, :user_id,
           :region_id, :to_trash, :trash_after, :size, :usage, :usage_checked,
           :trashed_by_id, :detached_at, :subscription_id, :enable_sftp,
           :borg_enabled, :borg_freq, :borg_strategy, :borg_keep_annually,
           :borg_keep_daily, :borg_keep_hourly, :borg_keep_weekly, :borg_keep_monthly,
           :borg_pre_backup, :borg_post_backup, :borg_pre_restore, :borg_post_restore,
           :borg_rollback, :created_at, :updated_at

child :volume_maps, object_root: false do
  attributes :id, :mount_ro, :mount_path
  child :container_service do
    attributes :id, :csrn, :name, :label
  end
end

child :template do
  attributes :id, :csrn
  child :container_image do
    attributes :id, :csrn, :label
  end
end

child :user do
  extends 'api/admin/users/short'
end
