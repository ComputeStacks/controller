class UpdateVolumeProjects < ActiveRecord::Migration[7.0]
  def change

    puts "Mapping volumes to projects"
    Volume.all.each do |vol|
      m = vol.volume_maps.primary.first
      next if m.nil?
      next if m.deployment.nil?
      vol.update_column :deployment_id, m.deployment.id
    end

    puts "Rebuilding sftp containers"
    Deployment::Sftp.all.each do |sftp|
      audit = Audit.create_from_object! sftp, 'updated', '127.0.0.1'
      PowerCycleContainerService.new(sftp, 'rebuild', audit).perform
    end
  end
end
