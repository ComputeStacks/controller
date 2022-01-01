attributes :id, :name, :active, :fill_to, :volume_backend, :nfs_remote_host, :nfs_remote_path, :nfs_controller_ip, :offline_window, :failure_count, :loki_endpoint, :loki_retries, :loki_batch_size, :log_client_id, :metric_client_id, :disable_oom, :pid_limit, :ulimit_nofile_soft, :ulimit_nofile_hard, :created_at, :updated_at
child :networks do
  attributes :id, :name
end
child :user_groups do
  attributes :id, :name
end

