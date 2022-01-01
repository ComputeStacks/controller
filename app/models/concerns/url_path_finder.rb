module UrlPathFinder
  extend ActiveSupport::Concern

  ##
  # Used by Audit to generate a link
  def url_path(current_user)
    case self.class.to_s
    when "ContainerImage"
      "#{current_user.is_admin? ? '/admin' : ''}/container_images/#{id}-#{name.parameterize}"
    when "Deployment"
      "#{current_user.is_admin? ? '/admin' : ''}/deployments/#{id}"
    when "Deployment::Container"
      "#{current_user.is_admin? ? '/admin' : ''}/containers/#{id}"
    when "Deployment::Sftp"
      "#{current_user.is_admin? ? '/admin' : ''}/sftp/#{id}"
    when "Order"
      "#{current_user.is_admin? ? '/admin' : ''}/orders/#{id}"
    when "User"
      return nil unless current_user.is_admin
      "/admin/users/#{id}-#{full_name.parameterize}"
    when "Volume"
      "#{current_user.is_admin? ? '/admin' : ''}/volumes/#{id}"
    else
      nil
    end
  end

end
