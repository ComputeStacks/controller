module AdminAuthable
  extend ActiveSupport::Concern

  included do
    before_action :check_admin
  end

  private

  def check_admin
    if current_user&.is_admin
      unless Feature.check('admin', current_user)
        redirect_to "/deployments", alert: 'Admin interface disabled.'
        return false
      end
    else
      redirect_to "/deployments", :alert => "Invalid URL"
      return false
    end
  end

end