class AddWpEcKey < ActiveRecord::Migration[6.1]
  def change
    ContainerImage.where(registry_image_path: "cmptstks/wordpress", registry_image_tag: "php7.4-litespeed").each do |image|
      next if image.env_params.where(name: "CS_AUTH_KEY").exists?
      image.env_params.create!(
        name:       'CS_AUTH_KEY',
        param_type: 'variable',
        env_value:  'build.self.ec_pub_key'
      )
    end
  end
end
