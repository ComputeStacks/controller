class MigrateIngressRuleRegions < ActiveRecord::Migration[6.1]
  def change
    Network::IngressRule.all.each do |i|
      if i.container_service
        i.update region: i.container_service.region
      elsif i.sftp_container
        i.update region: i.sftp_container.region
      else
        puts "Ingress rule #{i.id} has no region."
      end
    end
  end
end
