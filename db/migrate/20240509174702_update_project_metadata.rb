class UpdateProjectMetadata < ActiveRecord::Migration[7.1]
  def change
    Deployment.all.each do |i|
      ProjectServices::StoreMetadata.new(i).perform
      sleep 0.5 # Lets not flood consul too quickly.
    end
  end
end
