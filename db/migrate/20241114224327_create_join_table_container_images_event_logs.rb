class CreateJoinTableContainerImagesEventLogs < ActiveRecord::Migration[7.1]
  def change
    create_join_table :container_images, :event_logs do |t|
      t.index [:container_image_id, :event_log_id], unique: true
      t.index [:event_log_id, :container_image_id], unique: true
    end
  end
end
