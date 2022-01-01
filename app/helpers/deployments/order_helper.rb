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

end
