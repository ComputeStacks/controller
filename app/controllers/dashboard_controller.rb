class DashboardController < AuthController

  def default_route
    redirect_to "/deployments"
  end

end
