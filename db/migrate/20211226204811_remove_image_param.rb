class RemoveImageParam < ActiveRecord::Migration[6.1]
  def change
    drop_table :container_image_image_params
  end
end
