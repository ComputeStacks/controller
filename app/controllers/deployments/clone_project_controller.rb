class Deployments::CloneProjectController < Deployments::BaseController

  def create

    audit = Audit.create_from_object! @deployment, 'clone', request.remote_ip, current_user
    clone_service = ProjectServices::CloneProjectService.new(@deployment, audit)
    clone_service.perform
    event = clone_service.event
    if clone_service.errors.empty?
      event.done!
      session[:deployment_order] = clone_service.order_session.id
      # render plain: clone_service.order_session.id
      redirect_to "/deployments/orders/containers"
    else
      event.fail! "Error"
      redirect_to "/deployments/#{@deployment.token}", alert: "Clone Error: #{clone_service.errors.join(", ")}"
    end

  end

end
