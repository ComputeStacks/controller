class AddEdgeHeaderTogglesToContainerDomains < ActiveRecord::Migration[7.2]
  def change
    add_column :deployment_container_domains, :hsts_include_subdomains, :boolean, default: false, null: false
    add_column :deployment_container_domains, :hsts_preload, :boolean, default: false, null: false
    add_column :deployment_container_domains, :header_frame_options, :boolean, default: false, null: false
  end
end
