class CleanOrphanedCollabs < ActiveRecord::Migration[6.1]
  def change

    ContainerImageCollaborator.all.each do |i|
      next unless i.collaborator.nil?
      i.delete
    end

    ContainerRegistryCollaborator.all.each do |i|
      next unless i.collaborator.nil?
      i.delete
    end

    DeploymentCollaborator.all.each do |i|
      next unless i.collaborator.nil?
      i.delete
    end

    Dns::ZoneCollaborator.all.each do |i|
      next unless i.collaborator.nil?
      i.delete
    end

  end
end
