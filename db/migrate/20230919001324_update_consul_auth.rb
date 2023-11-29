class UpdateConsulAuth < ActiveRecord::Migration[7.0]
  def change

    ##
    # Ensure we have the new bastion config loaded
    Setting.computestacks_bastion_image

    ##
    # Add write permission to all existing keys
    Deployment.all.each do |project|
      d = {
        'ID' => project.consul_policy_id,
        'Name' => "proj-#{project.token}",
        'Description' => "MetaData Policy for Project #{project.name}",
        'Rules' => %Q(key_prefix "projects/#{project.token}/" { policy = "read" } key_prefix "projects/#{project.token}/db/" { policy = "write" })
      }
      Diplomat::Policy.update d, project.region.consul_config
    end

  end
end
