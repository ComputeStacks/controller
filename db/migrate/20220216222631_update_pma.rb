class UpdatePma < ActiveRecord::Migration[6.1]
  def change
    ContainerImage.where(registry_image_path: "cmptstks/phpmyadmin").each do |i|
      i.update_column :registry_image_tag, "v2"
      i.env_params.each do |ii|
        next unless %w(BASE_URL HOSTNAME API_URL).include?(ii.name)
        ii.delete
      end
    end
  end
end
