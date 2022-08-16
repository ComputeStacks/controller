class RebuildSftpContainers < ActiveRecord::Migration[6.1]
  def change
    Deployment::Sftp.all.each do |sftp|
      audit = Audit.create_from_object! sftp, 'updated', '127.0.0.1'
      PowerCycleContainerService.new(sftp, 'rebuild', audit).perform
    end
  end
end
