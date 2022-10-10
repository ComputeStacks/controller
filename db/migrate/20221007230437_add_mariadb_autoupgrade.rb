class AddMariadbAutoupgrade < ActiveRecord::Migration[7.0]
  def change
    ContainerImage.where(registry_image_path: "mariadb").each do |image|

      next if image.env_params.where(name: "MARIADB_AUTO_UPGRADE").exists?
      p = image.env_params.create!(
        name: "MARIADB_AUTO_UPGRADE",
        label: "MARIADB_AUTO_UPGRADE",
        param_type: "static",
        static_value: "true"
      )

      image.deployed_services.each do |service|
        next if service.env_params.where(name: 'MARIADB_AUTO_UPGRADE').exists?
        service.env_params.create!(
          parent_param: p,
          param_type: 'static',
          name: 'MARIADB_AUTO_UPGRADE',
          static_value: 'true'
        )
      end

    end
  end
end
