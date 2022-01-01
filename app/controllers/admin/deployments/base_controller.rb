class Admin::Deployments::BaseController < Admin::ApplicationController

	before_action :load_deployment

	private

	def load_deployment
		@deployment = Deployment.find_by(id: params[:deployment_id])
		if @deployment.nil?
			if request.xhr?
				return render(plain: 'Project not found.', layout: false)
			else
				return redirect_to("/admin/deployments")
			end
		end
		@base_url = "/admin/deployments/#{@deployment.id}-#{@deployment.name.to_param}"
	end

end
