class Admin::Deployments::DomainsController < Admin::Deployments::BaseController

	before_action :find_domain, only: %w(show edit update destroy)
	before_action :load_project_services, only: %w(new edit update create)

	def index
		@domains = @deployment.domains.sorted
		return(render template: "admin/deployments/domains/index", layout: false) if params[:js]
	end

	def new
		@domain = @deployment.user.container_domains.new
		render template: "admin/container_domains/new"
	end

	def edit
		render template: "admin/container_domains/edit"
	end

	private

	def find_domain
		@domain = @deployment.domains.find_by(id: params[:id])
		@base_url = "/admin/deployments/#{@deployment.id}-#{@deployment.name.parameterize}"
		return redirect_to(@base_url, alert: "Unknown domain") if @domain.nil?
		@domain.current_user = current_user
		@services = @domain.user.container_services.sorted
	end

	def load_project_services
		if @domain && @domain.ingress_rule&.container_service
			@service = @domain.ingress_rule.container_service
		elsif params[:service_id]
			@service = @deployment.services.find_by(id: params[:service_id])
		end
		@services = @deployment.services.web_only.sorted
		@ingress_rules = if @service
			@service.ingress_rules.where(external_access: true)
		else
			[]
		end
	end

end
