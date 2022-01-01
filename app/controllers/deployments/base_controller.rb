# Legacy base controller
class Deployments::BaseController < AuthController

  before_action :find_deployment

  private

  def find_deployment
    @deployment = Deployment.find_for current_user, { token: params[:deployment_id] }
    if @deployment.nil?
      return respond_to do |format|
        format.json { head :unauthorized }
        format.xml {  head :unauthorized }
        format.html { redirect_to("/deployments") }
      end
    end
  end

end
