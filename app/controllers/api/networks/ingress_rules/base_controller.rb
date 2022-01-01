class Api::Networks::IngressRules::BaseController < Api::ApplicationController

	before_action :find_ingress_rule

	private

	def find_ingress_rule
		@ingress_rule = Network::IngressRule.find(params[:ingress_rule_id])
		if @ingress_rule.container_service
			return api_obj_missing unless @ingress_rule.container_service.can_edit?(current_user)
		elsif @ingress_rule.sftp_container
			return api_obj_missing unless @ingress_rule.sftp_container.can_edit?(current_user)
		else
			return api_obj_missing
		end
	end

end
