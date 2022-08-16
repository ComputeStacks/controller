# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2022_08_16_045546) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "uuid-ossp"

  create_table "alert_notifications", force: :cascade do |t|
    t.string "status"
    t.string "fingerprint"
    t.string "name"
    t.bigint "container_id"
    t.bigint "sftp_container_id"
    t.bigint "node_id"
    t.string "service"
    t.string "severity"
    t.text "description"
    t.decimal "value"
    t.jsonb "labels", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "event_count", default: 1, null: false
    t.datetime "last_event", precision: nil, null: false
    t.index ["container_id"], name: "index_alert_notifications_on_container_id"
    t.index ["fingerprint"], name: "index_alert_notifications_on_fingerprint", unique: true
    t.index ["labels"], name: "index_alert_notifications_on_labels", using: :gin
    t.index ["sftp_container_id"], name: "index_alert_notifications_on_sftp_container_id"
    t.index ["status"], name: "index_alert_notifications_on_status"
  end

  create_table "alert_notifications_event_logs", id: false, force: :cascade do |t|
    t.bigint "alert_notification_id", null: false
    t.bigint "event_log_id", null: false
    t.index ["alert_notification_id", "event_log_id"], name: "alert_events_index"
    t.index ["event_log_id", "alert_notification_id"], name: "event_alerts_index"
  end

  create_table "audits", id: :serial, force: :cascade do |t|
    t.inet "ip_addr"
    t.integer "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "rel_id"
    t.string "rel_model"
    t.string "event"
    t.text "raw_data"
    t.uuid "rel_uuid"
    t.index ["ip_addr"], name: "index_audits_on_ip_addr"
    t.index ["rel_uuid"], name: "index_audits_on_rel_uuid"
    t.index ["user_id"], name: "index_audits_on_user_id"
  end

  create_table "billing_events", force: :cascade do |t|
    t.integer "user_id"
    t.bigint "subscription_product_id"
    t.boolean "from_status"
    t.boolean "to_status"
    t.integer "from_product_id"
    t.integer "to_product_id"
    t.string "from_phase"
    t.string "to_phase"
    t.decimal "from_resource_qty"
    t.decimal "to_resource_qty"
    t.string "resource_type"
    t.integer "rel_id"
    t.string "rel_model"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "subscription_id"
    t.bigint "audit_id"
    t.index ["audit_id"], name: "index_billing_events_on_audit_id"
    t.index ["subscription_product_id"], name: "index_billing_events_on_subscription_product_id"
    t.index ["user_id"], name: "index_billing_events_on_user_id"
  end

  create_table "billing_packages", id: :serial, force: :cascade do |t|
    t.integer "product_id"
    t.decimal "cpu"
    t.integer "memory"
    t.integer "storage"
    t.integer "bandwidth"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "backup", default: 0, null: false
    t.integer "local_disk", default: 0, null: false
    t.integer "memory_swap"
    t.integer "memory_swappiness"
  end

  create_table "billing_phases", id: :serial, force: :cascade do |t|
    t.integer "billing_resource_id"
    t.string "phase_type", default: "final", null: false
    t.string "duration_unit"
    t.integer "duration_qty"
    t.boolean "new_user_only", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["billing_resource_id"], name: "index_billing_phases_on_billing_resource_id"
  end

  create_table "billing_plans", id: :serial, force: :cascade do |t|
    t.string "name"
    t.boolean "is_default", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "billing_resource_prices", id: :serial, force: :cascade do |t|
    t.integer "billing_phase_id"
    t.integer "billing_resource_id"
    t.string "currency", default: "USD", null: false
    t.decimal "max_qty"
    t.decimal "price", default: "0.0", null: false
    t.string "term", default: "month", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["billing_phase_id"], name: "index_billing_resource_prices_on_billing_phase_id"
    t.index ["billing_resource_id"], name: "index_billing_resource_prices_on_billing_resource_id"
  end

  create_table "billing_resource_prices_regions", id: false, force: :cascade do |t|
    t.integer "billing_resource_price_id", null: false
    t.integer "region_id", null: false
    t.index ["billing_resource_price_id", "region_id"], name: "index_bilresourceprice_region"
    t.index ["region_id", "billing_resource_price_id"], name: "index_region_bilresourceprice"
  end

  create_table "billing_resources", id: :serial, force: :cascade do |t|
    t.integer "billing_plan_id"
    t.integer "product_id"
    t.string "external_id"
    t.decimal "val_min", default: "0.0", null: false
    t.decimal "val_max", default: "1.0", null: false
    t.decimal "val_step", default: "1.0", null: false
    t.decimal "val_default", default: "0.0", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["billing_plan_id"], name: "index_billing_resources_on_billing_plan_id"
    t.index ["product_id"], name: "index_billing_resources_on_product_id"
  end

  create_table "billing_usages", force: :cascade do |t|
    t.integer "user_id"
    t.datetime "period_start", precision: nil
    t.datetime "period_end", precision: nil
    t.bigint "subscription_product_id"
    t.string "external_id"
    t.decimal "rate", default: "0.0", null: false
    t.decimal "qty", default: "0.0", null: false
    t.decimal "total", default: "0.0", null: false
    t.boolean "processed", default: false, null: false
    t.datetime "processed_on", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.decimal "qty_total", default: "0.0", null: false
    t.index ["processed"], name: "index_billing_usages_on_procesed"
    t.index ["subscription_product_id"], name: "index_billing_usages_on_subscription_product_id"
    t.index ["user_id"], name: "index_billing_usages_on_user_id"
  end

  create_table "block_contents", force: :cascade do |t|
    t.bigint "block_id", null: false
    t.text "body"
    t.string "locale", default: "en", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["block_id"], name: "index_block_contents_on_block_id"
    t.index ["locale"], name: "index_block_contents_on_locale"
  end

  create_table "blocks", force: :cascade do |t|
    t.string "title"
    t.string "content_key"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "container_image_collaborators", force: :cascade do |t|
    t.bigint "container_image_id"
    t.bigint "user_id"
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_container_image_collaborators_on_active"
    t.index ["container_image_id", "user_id"], name: "image_collab_img_user", unique: true
  end

  create_table "container_image_custom_host_entries", force: :cascade do |t|
    t.bigint "container_image_id"
    t.string "hostname"
    t.bigint "source_image_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["container_image_id"], name: "index_container_image_custom_host_entries_on_container_image_id"
    t.index ["source_image_id"], name: "index_container_image_custom_host_entries_on_source_image_id"
  end

  create_table "container_image_env_params", force: :cascade do |t|
    t.bigint "container_image_id"
    t.string "name"
    t.string "label"
    t.string "param_type", default: "static", null: false
    t.text "value"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["container_image_id"], name: "ciep_image_id"
  end

  create_table "container_image_image_rels", id: :serial, force: :cascade do |t|
    t.integer "container_image_id"
    t.integer "requires_container_id"
    t.boolean "optional", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["container_image_id"], name: "index_container_image_image_rels_on_container_image_id"
    t.index ["requires_container_id"], name: "index_container_image_image_rels_on_requires_container_id"
  end

  create_table "container_image_ingress_params", force: :cascade do |t|
    t.bigint "container_image_id"
    t.bigint "load_balancer_rule_id"
    t.boolean "external_access", default: false, null: false
    t.string "proto", null: false
    t.boolean "backend_ssl", default: false, null: false
    t.integer "port", null: false
    t.string "tcp_proxy_opt", default: "none", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "tcp_lb", default: true, null: false
    t.index ["container_image_id"], name: "index_container_image_ingress_params_on_container_image_id"
    t.index ["external_access"], name: "index_container_image_ingress_params_on_external_access"
    t.index ["load_balancer_rule_id"], name: "index_container_image_ingress_params_on_load_balancer_rule_id"
  end

  create_table "container_image_providers", force: :cascade do |t|
    t.string "name"
    t.boolean "is_default", default: false
    t.string "hostname"
    t.bigint "container_registry_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "active", default: true, null: false
    t.index ["active"], name: "index_container_image_providers_on_active"
    t.index ["container_registry_id"], name: "index_container_image_providers_on_container_registry_id"
    t.index ["is_default"], name: "index_container_image_providers_on_is_default"
    t.index ["name"], name: "index_container_image_providers_on_name"
  end

  create_table "container_image_setting_params", force: :cascade do |t|
    t.bigint "container_image_id"
    t.string "name"
    t.string "label"
    t.string "param_type", default: "static", null: false
    t.text "value"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["container_image_id"], name: "cisp_image_id"
  end

  create_table "container_image_volume_params", force: :cascade do |t|
    t.bigint "container_image_id"
    t.string "mount_path", default: "/mnt", null: false
    t.string "label"
    t.boolean "borg_enabled", default: true
    t.string "borg_freq", default: "@hourly", null: false
    t.string "borg_strategy", default: "file", null: false
    t.integer "borg_keep_hourly", default: 1, null: false
    t.integer "borg_keep_daily", default: 1, null: false
    t.integer "borg_keep_weekly", default: 1, null: false
    t.integer "borg_keep_monthly", default: 1, null: false
    t.integer "borg_keep_annually", default: 1, null: false
    t.boolean "borg_backup_error", default: false, null: false
    t.boolean "borg_restore_error", default: false, null: false
    t.text "borg_pre_backup", default: [], null: false, array: true
    t.text "borg_post_backup", default: [], null: false, array: true
    t.text "borg_pre_restore", default: [], null: false, array: true
    t.text "borg_post_restore", default: [], null: false, array: true
    t.text "borg_rollback", default: [], null: false, array: true
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "enable_sftp", default: true, null: false
    t.boolean "mount_ro", default: false, null: false
    t.bigint "source_volume_id"
    t.index ["container_image_id"], name: "index_container_image_volume_params_on_container_image_id"
    t.index ["enable_sftp"], name: "civp_enable_sftp"
    t.index ["source_volume_id"], name: "index_container_image_volume_params_on_source_volume_id"
  end

  create_table "container_images", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "label"
    t.text "description"
    t.string "image_url"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "role"
    t.string "role_class"
    t.boolean "featured", default: false
    t.integer "container_registry_id"
    t.boolean "lb_req", default: false
    t.boolean "can_scale", default: false, null: false
    t.boolean "is_free", default: false, null: false
    t.integer "user_id"
    t.boolean "enable_sftp", default: true, null: false
    t.bigint "general_block_id"
    t.bigint "remote_block_id"
    t.bigint "ssh_block_id"
    t.bigint "domains_block_id"
    t.string "registry_username", default: "admin"
    t.bigint "container_image_provider_id"
    t.string "registry_custom"
    t.string "registry_image_path"
    t.string "registry_image_tag", default: "latest"
    t.boolean "registry_auth", default: false
    t.decimal "min_cpu", default: "0.0", null: false
    t.integer "min_memory", default: 0, null: false
    t.string "command"
    t.text "registry_password_encrypted"
    t.boolean "is_load_balancer", default: false, null: false
    t.jsonb "labels", default: {}, null: false
    t.boolean "validated_tag", default: true, null: false
    t.datetime "validated_tag_updated", precision: nil
    t.boolean "force_local_volume", default: false, null: false
    t.boolean "override_autoremove", default: false, null: false
    t.index ["container_image_provider_id"], name: "index_container_images_on_container_image_provider_id"
    t.index ["is_load_balancer"], name: "index_container_images_on_is_load_balancer"
    t.index ["labels"], name: "index_container_images_on_labels", using: :gin
    t.index ["registry_image_path", "registry_image_tag"], name: "by_image_and_tag"
    t.index ["validated_tag", "validated_tag_updated"], name: "container_image_tag_validation_index"
  end

  create_table "container_registries", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "label"
    t.integer "port"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "status", default: "new", null: false
    t.integer "user_id"
    t.text "password_encrypted"
    t.index ["name"], name: "index_container_registries_on_name"
  end

  create_table "container_registries_event_logs", id: false, force: :cascade do |t|
    t.bigint "container_registry_id", null: false
    t.bigint "event_log_id", null: false
    t.index ["container_registry_id", "event_log_id"], name: "index_cr_logs"
    t.index ["event_log_id", "container_registry_id"], name: "index_logs_cr"
  end

  create_table "container_registry_collaborators", force: :cascade do |t|
    t.bigint "container_registry_id"
    t.bigint "user_id"
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_container_registry_collaborators_on_active"
    t.index ["container_registry_id", "user_id"], name: "cr_collab_reg_user", unique: true
  end

  create_table "container_service_env_configs", force: :cascade do |t|
    t.bigint "container_service_id"
    t.string "name"
    t.string "label"
    t.string "param_type", default: "static", null: false
    t.text "value"
    t.bigint "container_image_env_param_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["container_image_env_param_id"], name: "csec_image_param_id"
    t.index ["container_service_id"], name: "csec_service_id"
  end

  create_table "container_service_host_entries", force: :cascade do |t|
    t.bigint "container_service_id"
    t.bigint "template_id"
    t.string "hostname"
    t.string "ipaddr"
    t.boolean "keep_updated", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["container_service_id"], name: "index_container_service_host_entries_on_container_service_id"
    t.index ["template_id"], name: "index_container_service_host_entries_on_template_id"
  end

  create_table "container_service_setting_configs", force: :cascade do |t|
    t.bigint "container_service_id"
    t.string "name"
    t.string "label"
    t.string "param_type", default: "static", null: false
    t.text "value"
    t.bigint "container_image_setting_param_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["container_image_setting_param_id"], name: "cssc_setting_param"
    t.index ["container_service_id"], name: "cssc_service_id"
  end

  create_table "deployment_collaborators", force: :cascade do |t|
    t.bigint "deployment_id"
    t.bigint "user_id"
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_deployment_collaborators_on_active"
    t.index ["deployment_id", "user_id"], name: "index_deployment_collaborators_on_deployment_id_and_user_id", unique: true
  end

  create_table "deployment_container_domains", id: :serial, force: :cascade do |t|
    t.string "domain"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "system_domain", default: false
    t.boolean "le_enabled", default: false, null: false
    t.datetime "le_ready_checked", precision: nil
    t.boolean "le_ready", default: false, null: false
    t.boolean "enabled", default: true, null: false
    t.bigint "user_id"
    t.bigint "ingress_rule_id"
    t.boolean "header_hsts", default: false
    t.bigint "lets_encrypt_id"
    t.boolean "force_https", default: false, null: false
    t.index ["enabled"], name: "index_deployment_container_domains_on_enabled"
    t.index ["ingress_rule_id"], name: "index_deployment_container_domains_on_ingress_rule_id"
    t.index ["le_enabled"], name: "index_deployment_container_domains_on_le_enabled"
    t.index ["le_ready"], name: "index_deployment_container_domains_on_le_ready"
    t.index ["lets_encrypt_id"], name: "index_deployment_container_domains_on_lets_encrypt_id"
    t.index ["user_id"], name: "index_deployment_container_domains_on_user_id"
  end

  create_table "deployment_container_domains_event_logs", id: false, force: :cascade do |t|
    t.bigint "deployment_container_domain_id", null: false
    t.bigint "event_log_id", null: false
    t.index ["deployment_container_domain_id", "event_log_id"], name: "container_domains_event_logs"
    t.index ["event_log_id", "deployment_container_domain_id"], name: "event_logs_container_domains"
  end

  create_table "deployment_container_links", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "service_id"
    t.bigint "service_resource_id"
  end

  create_table "deployment_container_services", force: :cascade do |t|
    t.bigint "deployment_id"
    t.bigint "container_image_id"
    t.string "name"
    t.string "label"
    t.string "status", default: "pending", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.decimal "cpu"
    t.integer "memory"
    t.bigint "initial_subscription_id"
    t.boolean "active", default: true, null: false
    t.bigint "master_domain_id"
    t.string "command"
    t.integer "region_id"
    t.integer "load_balancer_id"
    t.boolean "is_load_balancer", default: false, null: false
    t.jsonb "labels", default: {}, null: false
    t.boolean "auto_scale", default: false, null: false
    t.boolean "auto_scale_horizontal", default: true, null: false
    t.decimal "auto_scale_max", default: "0.0", null: false
    t.boolean "override_autoremove", default: false, null: false
    t.index ["container_image_id"], name: "index_deployment_container_services_on_container_image_id"
    t.index ["deployment_id"], name: "index_deployment_container_services_on_deployment_id"
    t.index ["is_load_balancer"], name: "index_deployment_container_services_on_is_load_balancer"
    t.index ["labels"], name: "index_deployment_container_services_on_labels", using: :gin
    t.index ["load_balancer_id"], name: "index_deployment_container_services_on_load_balancer_id"
    t.index ["master_domain_id"], name: "index_deployment_container_services_on_master_domain_id"
    t.index ["region_id"], name: "index_deployment_container_services_on_region_id"
  end

  create_table "deployment_container_services_event_logs", id: false, force: :cascade do |t|
    t.bigint "deployment_container_service_id", null: false
    t.bigint "event_log_id", null: false
    t.index ["deployment_container_service_id", "event_log_id"], name: "index_services_logs"
    t.index ["event_log_id", "deployment_container_service_id"], name: "index_logs_services"
  end

  create_table "deployment_container_stats", id: :serial, force: :cascade do |t|
    t.integer "container_id"
    t.bigint "network_rx", default: 0, null: false
    t.bigint "network_tx", default: 0, null: false
    t.bigint "memory_usage", default: 0, null: false
    t.bigint "memory_limit", default: 0, null: false
    t.decimal "memory", default: "0.0", null: false
    t.decimal "cpu_perc", default: "0.0", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "cpu_user_usage", default: 0
    t.bigint "cpu_system_usage", default: 0
  end

  create_table "deployment_containers", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "status"
    t.integer "failed_health_checks", default: 0, null: false
    t.inet "private_ip"
    t.integer "node_id"
    t.boolean "built", default: false, null: false
    t.decimal "cpu"
    t.integer "memory"
    t.bigint "subscription_id"
    t.bigint "container_service_id"
    t.string "req_state", default: "running", null: false
  end

  create_table "deployment_containers_event_logs", id: false, force: :cascade do |t|
    t.bigint "deployment_container_id", null: false
    t.bigint "event_log_id", null: false
    t.index ["deployment_container_id", "event_log_id"], name: "index_containers_logs"
    t.index ["event_log_id", "deployment_container_id"], name: "index_logs_containers"
  end

  create_table "deployment_sftp_host_keys", force: :cascade do |t|
    t.bigint "sftp_container_id"
    t.text "pkey", null: false
    t.text "pubkey", null: false
    t.string "algo", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sftp_container_id"], name: "index_deployment_sftp_host_keys_on_sftp_container_id"
  end

  create_table "deployment_sftps", id: :serial, force: :cascade do |t|
    t.string "name"
    t.integer "deployment_id"
    t.integer "node_id"
    t.string "status", default: "pending", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "to_trash", default: false
    t.string "req_state", default: "stopped", null: false
    t.boolean "built", default: false, null: false
    t.text "password_encrypted"
    t.integer "load_balancer_id"
    t.boolean "pw_auth", default: true, null: false
    t.index ["deployment_id"], name: "index_deployment_sftps_on_deployment_id"
    t.index ["node_id"], name: "index_deployment_sftps_on_node_id"
  end

  create_table "deployment_sftps_event_logs", id: false, force: :cascade do |t|
    t.bigint "deployment_sftp_id", null: false
    t.bigint "event_log_id", null: false
    t.index ["deployment_sftp_id", "event_log_id"], name: "index_sftp_logs"
    t.index ["event_log_id", "deployment_sftp_id"], name: "index_logs_sftp"
  end

  create_table "deployment_ssh_keys", force: :cascade do |t|
    t.bigint "deployment_id"
    t.string "label"
    t.text "pubkey", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deployment_id"], name: "index_deployment_ssh_keys_on_deployment_id"
  end

  create_table "deployment_ssls", force: :cascade do |t|
    t.bigint "container_service_id"
    t.datetime "not_before", precision: nil
    t.datetime "not_after", precision: nil
    t.string "cert_serial"
    t.string "issuer"
    t.string "subject"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "pkey_encrypted"
    t.text "ca"
    t.text "crt"
    t.index ["container_service_id"], name: "index_deployment_ssls_on_container_service_id"
  end

  create_table "deployments", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "status", default: "new", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "token"
    t.integer "user_id"
    t.boolean "skip_ssh", default: false, null: false
    t.string "consul_policy_id"
    t.string "consul_auth_id"
    t.string "consul_auth_key"
  end

  create_table "deployments_event_logs", id: false, force: :cascade do |t|
    t.bigint "deployment_id", null: false
    t.bigint "event_log_id", null: false
    t.index ["deployment_id", "event_log_id"], name: "index_deployments_logs"
    t.index ["event_log_id", "deployment_id"], name: "index_logs_deployments"
  end

  create_table "dns_zone_collaborators", force: :cascade do |t|
    t.bigint "dns_zone_id"
    t.bigint "user_id"
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_dns_zone_collaborators_on_active"
    t.index ["dns_zone_id", "user_id"], name: "index_dns_zone_collaborators_on_dns_zone_id_and_user_id", unique: true
  end

  create_table "dns_zones", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "provider_ref"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "provision_driver_id"
    t.binary "saved_state"
    t.datetime "saved_state_ts", precision: nil
    t.integer "user_id"
  end

  create_table "event_log_data", force: :cascade do |t|
    t.text "data"
    t.bigint "event_log_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "event_code"
    t.index ["event_code"], name: "index_event_log_data_on_event_code"
    t.index ["event_log_id"], name: "index_event_log_data_on_event_log_id"
  end

  create_table "event_logs", force: :cascade do |t|
    t.string "locale"
    t.string "status", default: "pending", null: false
    t.boolean "notice", default: false
    t.jsonb "locale_keys", default: {}
    t.bigint "audit_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "state_reason"
    t.string "event_code"
    t.index ["audit_id"], name: "index_event_logs_on_audit_id"
    t.index ["event_code"], name: "index_event_logs_on_event_code"
    t.index ["locale"], name: "index_event_logs_on_locale"
    t.index ["status"], name: "index_event_logs_on_status"
  end

  create_table "event_logs_lets_encrypts", id: false, force: :cascade do |t|
    t.bigint "event_log_id", null: false
    t.bigint "lets_encrypt_id", null: false
    t.index ["event_log_id", "lets_encrypt_id"], name: "event_logs_lets_encrypt"
    t.index ["lets_encrypt_id", "event_log_id"], name: "lets_encrypt_event_logs"
  end

  create_table "event_logs_load_balancers", id: false, force: :cascade do |t|
    t.bigint "event_log_id", null: false
    t.bigint "load_balancer_id", null: false
    t.index ["event_log_id", "load_balancer_id"], name: "index_logs_lb"
    t.index ["load_balancer_id", "event_log_id"], name: "index_lb_logs"
  end

  create_table "event_logs_nodes", id: false, force: :cascade do |t|
    t.bigint "event_log_id", null: false
    t.bigint "node_id", null: false
    t.index ["event_log_id", "node_id"], name: "index_logs_node"
    t.index ["node_id", "event_log_id"], name: "index_node_logs"
  end

  create_table "event_logs_users", id: false, force: :cascade do |t|
    t.bigint "event_log_id", null: false
    t.bigint "user_id", null: false
    t.index ["event_log_id", "user_id"], name: "index_logs_users"
    t.index ["user_id", "event_log_id"], name: "index_users_logs"
  end

  create_table "event_logs_volumes", id: false, force: :cascade do |t|
    t.bigint "event_log_id", null: false
    t.bigint "volume_id", null: false
    t.index ["event_log_id", "volume_id"], name: "index_logs_volumes"
    t.index ["volume_id", "event_log_id"], name: "index_volumes_logs"
  end

  create_table "features", id: :serial, force: :cascade do |t|
    t.string "name", limit: 255
    t.boolean "active", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "maintenance", default: false, null: false
    t.index ["name"], name: "index_features_on_name"
  end

  create_table "features_users", id: false, force: :cascade do |t|
    t.integer "feature_id"
    t.integer "user_id"
    t.index ["feature_id"], name: "index_features_users_on_feature_id"
    t.index ["user_id"], name: "index_features_users_on_user_id"
  end

  create_table "lets_encrypt_accounts", force: :cascade do |t|
    t.string "email"
    t.string "account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "pkey_encrypted"
  end

  create_table "lets_encrypt_auths", force: :cascade do |t|
    t.integer "lets_encrypt_id"
    t.string "domain"
    t.string "token"
    t.text "content"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "challenge_type", default: "http", null: false
    t.string "record_name"
    t.string "record_type", default: "TXT", null: false
    t.text "record_content"
    t.datetime "expires_at", precision: nil
    t.bigint "domain_id"
    t.index ["domain"], name: "index_lets_encrypt_auths_on_domain"
    t.index ["domain_id"], name: "index_lets_encrypt_auths_on_domain_id"
    t.index ["lets_encrypt_id"], name: "index_lets_encrypt_auths_on_lets_encrypt_id"
    t.index ["token"], name: "index_lets_encrypt_auths_on_token"
  end

  create_table "lets_encrypts", force: :cascade do |t|
    t.integer "account_id"
    t.integer "user_id"
    t.datetime "expires_at", precision: nil
    t.datetime "last_generated_at", precision: nil
    t.text "names", default: [], null: false, array: true
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "pkey_encrypted"
    t.text "crt"
    t.string "common_name"
    t.index ["account_id"], name: "index_lets_encrypts_on_account_id"
    t.index ["user_id"], name: "index_lets_encrypts_on_user_id"
  end

  create_table "load_balancer_addrs", force: :cascade do |t|
    t.bigint "load_balancer_id"
    t.inet "ip_addr"
    t.string "role"
    t.string "label"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["ip_addr"], name: "index_load_balancer_addrs_on_ip_addr"
    t.index ["load_balancer_id"], name: "index_load_balancer_addrs_on_load_balancer_id"
    t.index ["role"], name: "index_load_balancer_addrs_on_role"
  end

  create_table "load_balancers", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "label"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "region_id"
    t.text "ext_ip", default: "[]", null: false
    t.string "ext_config", default: "/etc/haproxy/haproxy.cfg"
    t.string "ext_reload_cmd", default: "bash -c 'if [[ -z $(pidof haproxy) ]]; then service haproxy start; else service haproxy reload; fi;'", null: false
    t.string "public_ip"
    t.string "ext_cert_dir", default: "/etc/haproxy/certs"
    t.string "ext_dir", default: "/etc/haproxy"
    t.string "job_status", default: "idle", null: false
    t.datetime "job_performed", precision: nil, default: "2018-05-11 21:16:37", null: false
    t.integer "cpus", default: 1, null: false
    t.integer "maxconn", default: 100000, null: false
    t.integer "maxconn_c", default: 200, null: false
    t.integer "ssl_cache", default: 1000000, null: false
    t.boolean "direct_connect", default: true, null: false
    t.boolean "le", default: false, null: false
    t.datetime "le_last_checked", precision: nil
    t.text "cert_encrypted"
    t.text "internal_ip", default: "[]", null: false
    t.boolean "proxy_cloudflare", default: true, null: false
    t.string "g_timeout_connect", default: "5s", null: false
    t.string "g_timeout_client", default: "150s", null: false
    t.string "g_timeout_server", default: "150s", null: false
    t.integer "max_queue", default: 50, null: false
    t.bigint "lets_encrypt_id"
    t.string "domain"
    t.boolean "domain_valid", default: true, null: false
    t.datetime "domain_valid_check", precision: nil
    t.string "stats_password", default: "wm0m2DOQb-Zbl4fqLGOYgqf", null: false
    t.string "stats_bind", default: "*:81", null: false
    t.boolean "proto_alpn", default: true, null: false
    t.boolean "proto_11", default: true, null: false
    t.boolean "proto_20", default: true, null: false
    t.boolean "proto_23", default: false, null: false
  end

  create_table "locations", force: :cascade do |t|
    t.string "name"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "fill_strategy", default: "least"
    t.boolean "fill_by_qty", default: true, null: false
    t.boolean "overcommit_cpu", default: true, null: false
    t.boolean "overcommit_memory", default: true, null: false
    t.index ["active"], name: "index_locations_on_active"
  end

  create_table "log_clients", force: :cascade do |t|
    t.string "endpoint", default: "http://localhost:3100", null: false
    t.string "username"
    t.string "password"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "metric_clients", force: :cascade do |t|
    t.string "endpoint", default: "http://localhost:9090", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.string "password"
  end

  create_table "network_cidrs", id: :serial, force: :cascade do |t|
    t.integer "network_id"
    t.inet "cidr", null: false
    t.integer "rel_id"
    t.string "rel_model"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "container_id"
    t.bigint "sftp_container_id"
    t.index ["container_id"], name: "index_network_cidrs_on_container_id"
    t.index ["network_id", "cidr"], name: "index_network_cidrs_on_network_id_and_cidr", unique: true
    t.index ["sftp_container_id"], name: "index_network_cidrs_on_sftp_container_id"
  end

  create_table "network_ingress_rules", force: :cascade do |t|
    t.bigint "ingress_param_id"
    t.bigint "container_service_id"
    t.bigint "sftp_container_id"
    t.bigint "load_balancer_rule_id"
    t.boolean "external_access", default: false, null: false
    t.string "proto", null: false
    t.boolean "backend_ssl", default: false, null: false
    t.integer "port", null: false
    t.integer "port_nat", default: 0, null: false
    t.string "tcp_proxy_opt", default: "none", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "restrict_cf", default: false, null: false
    t.boolean "tcp_lb", default: true, null: false
    t.bigint "region_id"
    t.index ["container_service_id"], name: "index_network_ingress_rules_on_container_service_id"
    t.index ["external_access", "load_balancer_rule_id", "proto"], name: "nir_by_external_access_lb_proto"
    t.index ["ingress_param_id"], name: "index_network_ingress_rules_on_ingress_param_id"
    t.index ["proto"], name: "index_network_ingress_rules_on_proto"
    t.index ["region_id"], name: "index_network_ingress_rules_on_region_id"
    t.index ["sftp_container_id"], name: "index_network_ingress_rules_on_sftp_container_id"
    t.index ["tcp_lb"], name: "index_network_ingress_rules_on_tcp_lb"
  end

  create_table "networks", id: :serial, force: :cascade do |t|
    t.string "cidr", default: "0.0.0.0/0", null: false
    t.boolean "is_public", default: false, null: false
    t.boolean "is_ipv4", default: true, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "name"
    t.string "label"
    t.boolean "cross_region", default: false, null: false
    t.index ["cross_region"], name: "index_networks_on_cross_region"
  end

  create_table "networks_regions", id: false, force: :cascade do |t|
    t.integer "network_id", null: false
    t.integer "region_id", null: false
    t.index ["network_id", "region_id"], name: "index_networks_regions_on_network_id_and_region_id"
    t.index ["region_id", "network_id"], name: "index_networks_regions_on_region_id_and_network_id"
  end

  create_table "nodes", id: :serial, force: :cascade do |t|
    t.string "label"
    t.string "hostname"
    t.string "primary_ip", default: "127.0.0.1", null: false
    t.boolean "disconnected", default: false, null: false
    t.integer "failed_health_checks", default: 0, null: false
    t.boolean "active", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "online_at", precision: nil
    t.datetime "disconnected_at", precision: nil
    t.string "public_ip", default: "127.0.0.1", null: false
    t.integer "region_id"
    t.integer "port_begin", default: 10000, null: false
    t.integer "port_end", default: 50000, null: false
    t.boolean "maintenance", default: false
    t.datetime "maintenance_updated", precision: nil
    t.string "job_status", default: "idle", null: false
    t.datetime "job_performed", precision: nil, default: "2018-05-12 18:22:20", null: false
    t.integer "ssh_port", default: 22, null: false
    t.string "volume_device"
    t.integer "block_write_bps", default: 0
    t.integer "block_read_bps", default: 0
    t.integer "block_write_iops", default: 0, null: false
    t.integer "block_read_iops", default: 0, null: false
  end

  create_table "nodes_volumes", id: false, force: :cascade do |t|
    t.bigint "node_id", null: false
    t.bigint "volume_id", null: false
    t.index ["node_id", "volume_id"], name: "index_nodes_volumes_on_node_id_and_volume_id"
    t.index ["volume_id", "node_id"], name: "index_nodes_volumes_on_volume_id_and_node_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "resource_owner_id", null: false
    t.bigint "application_id", null: false
    t.string "token", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "revoked_at", precision: nil
    t.string "scopes"
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "resource_owner_id"
    t.bigint "application_id", null: false
    t.string "token", null: false
    t.string "refresh_token"
    t.integer "expires_in"
    t.datetime "revoked_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.string "scopes"
    t.string "previous_refresh_token", default: "", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.string "name", null: false
    t.string "uid", null: false
    t.string "secret", null: false
    t.text "redirect_uri"
    t.string "scopes", default: "", null: false
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "owner_id"
    t.string "owner_type"
    t.index ["owner_id", "owner_type"], name: "index_oauth_applications_on_owner_id_and_owner_type"
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "orders", id: :uuid, default: -> { "uuid_generate_v4()" }, force: :cascade do |t|
    t.integer "deployment_id"
    t.string "status", default: "open", null: false
    t.integer "user_id"
    t.inet "ip_addr"
    t.text "order_data"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "external_id"
    t.integer "location_id"
    t.boolean "req_payment", default: false, null: false
    t.index ["location_id"], name: "index_orders_on_location_id"
  end

  create_table "product_modules", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "primary_id"
    t.index ["name"], name: "index_product_modules_on_name"
  end

  create_table "product_modules_provision_drivers", id: false, force: :cascade do |t|
    t.integer "product_module_id", null: false
    t.integer "provision_driver_id", null: false
  end

  create_table "products", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "label"
    t.string "kind"
    t.integer "unit"
    t.string "unit_type"
    t.boolean "is_aggregated", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "external_id"
    t.string "resource_kind"
    t.string "group"
    t.index ["group"], name: "index_products_on_group"
  end

  create_table "project_notifications", force: :cascade do |t|
    t.bigint "deployment_id", null: false
    t.string "label"
    t.string "value"
    t.string "notifier", default: "email", null: false
    t.text "rules", array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "provision_driver_user_auths", id: :serial, force: :cascade do |t|
    t.integer "provision_driver_id"
    t.string "username"
    t.string "api_key"
    t.string "api_secret"
    t.text "details", default: "{}", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["provision_driver_id"], name: "index_provision_driver_user_auths_on_provision_driver_id"
  end

  create_table "provision_drivers", id: :serial, force: :cascade do |t|
    t.string "endpoint"
    t.string "auth_type", default: "static", null: false
    t.string "settings", default: "{}", null: false
    t.string "module_name"
    t.string "username"
    t.string "api_key"
    t.string "api_secret"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "is_online", default: true
    t.datetime "offline_at", precision: nil
    t.datetime "online_at", precision: nil
  end

  create_table "regions", id: :serial, force: :cascade do |t|
    t.string "name", limit: 255
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "provision_driver_id"
    t.text "settings", default: "{}", null: false
    t.text "features", default: "{}", null: false
    t.integer "location_id"
    t.integer "fill_to", default: 500
    t.string "volume_backend", default: "local", null: false
    t.string "nfs_remote_host"
    t.string "nfs_remote_path", default: "/var/nfsshare/volumes", null: false
    t.integer "offline_window", default: 60
    t.integer "failure_count", default: 2
    t.string "nfs_controller_ip"
    t.string "loki_endpoint", default: "http://localhost:3100"
    t.string "loki_retries", default: "5", null: false
    t.string "loki_batch_size", default: "400", null: false
    t.bigint "log_client_id"
    t.bigint "metric_client_id"
    t.boolean "disable_oom", default: false, null: false
    t.integer "pid_limit", default: 0, null: false
    t.integer "ulimit_nofile_soft", default: 0, null: false
    t.integer "ulimit_nofile_hard", default: 0, null: false
    t.string "consul_token"
    t.index ["location_id"], name: "index_regions_on_location_id"
  end

  create_table "regions_user_groups", id: false, force: :cascade do |t|
    t.bigint "region_id", null: false
    t.bigint "user_group_id", null: false
    t.index ["region_id", "user_group_id"], name: "index_regions_user_groups_on_region_id_and_user_group_id"
    t.index ["user_group_id", "region_id"], name: "index_regions_user_groups_on_user_group_id_and_region_id"
  end

  create_table "regions_users", id: false, force: :cascade do |t|
    t.integer "region_id"
    t.integer "user_id"
    t.index ["region_id"], name: "index_regions_users_on_region_id"
    t.index ["user_id"], name: "index_regions_users_on_user_id"
  end

  create_table "secrets", id: :serial, force: :cascade do |t|
    t.string "key_name"
    t.text "encrypted_data"
    t.integer "rel_id"
    t.string "rel_model"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["rel_id", "rel_model"], name: "index_secrets_on_rel_id_and_rel_model"
  end

  create_table "sessions", id: :serial, force: :cascade do |t|
    t.string "session_id", null: false
    t.text "data"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["session_id"], name: "index_sessions_on_session_id", unique: true
    t.index ["updated_at"], name: "index_sessions_on_updated_at"
  end

  create_table "settings", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "category"
    t.text "description"
    t.text "value"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "encrypted", default: false, null: false
    t.index ["category"], name: "index_settings_on_category"
    t.index ["name"], name: "index_settings_on_name"
  end

  create_table "subscription_products", force: :cascade do |t|
    t.integer "product_id"
    t.bigint "subscription_id"
    t.string "external_id"
    t.datetime "start_on", precision: nil
    t.boolean "active", default: true, null: false
    t.string "phase_type"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["active"], name: "index_subscription_products_on_active"
    t.index ["product_id"], name: "index_subscription_products_on_product_id"
    t.index ["subscription_id"], name: "index_subscription_products_on_subscription_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "label"
    t.string "external_id"
    t.boolean "active", default: true, null: false
    t.text "details"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "service_key"
    t.index ["active"], name: "index_subscriptions_on_active"
    t.index ["service_key"], name: "index_subscriptions_on_service_key"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "system_events", force: :cascade do |t|
    t.string "message"
    t.text "data"
    t.string "log_level", default: "info"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "audit_id"
    t.string "event_code"
    t.index ["audit_id"], name: "index_system_events_on_audit_id"
    t.index ["event_code"], name: "index_system_events_on_event_code"
    t.index ["log_level"], name: "index_system_events_on_log_level"
  end

  create_table "system_notifications", force: :cascade do |t|
    t.string "label"
    t.string "value"
    t.string "notifier", default: "email", null: false
    t.text "rules", array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "taggings", id: :serial, force: :cascade do |t|
    t.integer "tag_id"
    t.string "taggable_type"
    t.integer "taggable_id"
    t.string "tagger_type"
    t.integer "tagger_id"
    t.string "context"
    t.datetime "created_at", precision: nil
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "index_taggings_on_taggable_id_and_taggable_type_and_context"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
  end

  create_table "tags", id: :serial, force: :cascade do |t|
    t.string "name"
    t.integer "taggings_count", default: 0
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "user_api_credentials", force: :cascade do |t|
    t.bigint "user_id"
    t.string "name"
    t.string "username"
    t.string "password"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["user_id"], name: "index_user_api_credentials_on_user_id"
    t.index ["username"], name: "index_user_api_credentials_on_username", unique: true
  end

  create_table "user_groups", force: :cascade do |t|
    t.string "name"
    t.boolean "is_default", default: false, null: false
    t.integer "billing_plan_id"
    t.boolean "active", default: true
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "q_containers", default: 250
    t.integer "q_dns_zones", default: 250
    t.integer "q_cr", default: 20
    t.boolean "allow_local_volume", default: false, null: false
    t.boolean "bill_offline", default: true, null: false
    t.boolean "bill_suspended", default: true, null: false
    t.boolean "remove_stopped", default: false, null: false
    t.index ["active"], name: "index_user_groups_on_active"
    t.index ["is_default"], name: "index_user_groups_on_is_default"
  end

  create_table "user_notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "label"
    t.string "value"
    t.string "notifier", default: "email", null: false
    t.text "rules", array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_security_keys", force: :cascade do |t|
    t.integer "user_id"
    t.string "public_key"
    t.integer "counter"
    t.string "label"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "webauthn_id"
    t.index ["webauthn_id"], name: "index_user_security_keys_on_webauthn_id"
  end

  create_table "user_ssh_keys", force: :cascade do |t|
    t.bigint "user_id"
    t.string "label"
    t.text "pubkey", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_ssh_keys_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "fname", limit: 255
    t.string "lname", limit: 255
    t.string "timezone", limit: 255, default: "UTC", null: false
    t.string "lang", limit: 255, default: "en", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "last_request_at", precision: nil
    t.string "token", limit: 255, null: false
    t.string "locale", limit: 255, default: "en", null: false
    t.string "email", limit: 255, default: "", null: false
    t.string "encrypted_password", limit: 255, default: "", null: false
    t.string "reset_password_token", limit: 255
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.inet "current_sign_in_ip"
    t.inet "last_sign_in_ip"
    t.string "confirmation_token", limit: 255
    t.datetime "confirmed_at", precision: nil
    t.datetime "confirmation_sent_at", precision: nil
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token", limit: 255
    t.datetime "locked_at", precision: nil
    t.boolean "is_admin", default: false, null: false
    t.string "currency", default: "USD", null: false
    t.string "api_key"
    t.string "api_secret"
    t.integer "api_version", default: 0, null: false
    t.string "external_id"
    t.string "auth_token"
    t.datetime "auth_token_exp", precision: nil
    t.string "country", default: "US", null: false
    t.boolean "bypass_billing", default: false
    t.string "city"
    t.string "state"
    t.string "address1"
    t.string "address2"
    t.string "zip"
    t.boolean "req_second_factor", default: false, null: false
    t.datetime "last_second_factor_auth", precision: nil
    t.boolean "bypass_second_factor", default: false
    t.string "vat"
    t.datetime "phase_started", precision: nil
    t.integer "user_group_id"
    t.text "comments"
    t.cidr "last_request_ip"
    t.string "company_name"
    t.string "phone"
    t.jsonb "labels", default: {}, null: false
    t.text "otp_secret_enc"
    t.integer "last_otp_at", default: 1602721986
    t.string "webauthn_id"
    t.boolean "c_sftp_pass", default: true, null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["labels"], name: "index_users_on_labels", using: :gin
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["token"], name: "index_users_on_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.index ["user_group_id"], name: "index_users_on_user_group_id"
  end

  create_table "volume_maps", force: :cascade do |t|
    t.bigint "volume_id"
    t.bigint "container_service_id"
    t.boolean "mount_ro", default: false, null: false
    t.string "mount_path"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_owner", default: false, null: false
    t.index ["container_service_id"], name: "index_volume_maps_on_container_service_id"
    t.index ["is_owner"], name: "index_volume_maps_on_is_owner"
    t.index ["volume_id"], name: "index_volume_maps_on_volume_id"
  end

  create_table "volumes", force: :cascade do |t|
    t.string "label"
    t.integer "user_id"
    t.integer "region_id"
    t.boolean "to_trash", default: false, null: false
    t.datetime "trash_after", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "name"
    t.decimal "usage", default: "0.0", null: false
    t.datetime "usage_checked", precision: nil
    t.bigint "trashed_by_id"
    t.datetime "detached_at", precision: nil
    t.bigint "subscription_id"
    t.boolean "borg_enabled", default: true
    t.string "borg_freq", default: "@hourly", null: false
    t.string "borg_strategy", default: "file", null: false
    t.integer "borg_keep_hourly", default: 1, null: false
    t.integer "borg_keep_daily", default: 1, null: false
    t.integer "borg_keep_weekly", default: 1, null: false
    t.integer "borg_keep_monthly", default: 1, null: false
    t.integer "borg_keep_annually", default: 1, null: false
    t.boolean "borg_backup_error", default: false
    t.boolean "borg_restore_error", default: false
    t.text "borg_pre_backup", default: [], array: true
    t.text "borg_post_backup", default: [], array: true
    t.text "borg_pre_restore", default: [], array: true
    t.text "borg_post_restore", default: [], array: true
    t.text "borg_rollback", default: [], array: true
    t.boolean "enable_sftp", default: true, null: false
    t.string "volume_backend", default: "local", null: false
    t.bigint "template_id"
    t.bigint "deployment_id"
    t.index ["borg_enabled"], name: "index_volumes_on_borg_enabled"
    t.index ["deployment_id"], name: "index_volumes_on_deployment_id"
    t.index ["enable_sftp"], name: "index_volumes_on_enable_sftp"
    t.index ["name"], name: "index_volumes_on_name"
    t.index ["region_id"], name: "index_volumes_on_region_id"
    t.index ["subscription_id"], name: "index_volumes_on_subscription_id"
    t.index ["template_id"], name: "index_volumes_on_template_id"
    t.index ["to_trash"], name: "index_volumes_on_to_trash"
    t.index ["trashed_by_id"], name: "index_volumes_on_trashed_by_id"
    t.index ["user_id"], name: "index_volumes_on_user_id"
    t.index ["volume_backend"], name: "index_volumes_on_volume_backend"
  end

  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id"
  add_foreign_key "user_api_credentials", "users"
end
