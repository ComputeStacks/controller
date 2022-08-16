module Deployments::OrderHelper

  def order_packages_for_resources(cpu, mem)
    data = {}
    packages = current_user.billing_plan.packages_by_resource cpu.to_f, mem.to_i
    packages.each do |i|
      g = i.product.group.nil? ? '' : i.product.group
      (data[g] ||= []) << i
    end
    data
  end

  ##
  # Skip password fields in order session
  def order_container_has_user_params?(container)
    container[:params].each_key do |i|
      return true unless container[:params][i][:type] == 'password'
    end
    false
  end

end
