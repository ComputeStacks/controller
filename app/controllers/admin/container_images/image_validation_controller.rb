class Admin::ContainerImages::ImageValidationController < Admin::ContainerImages::BaseController

	def create
		ImageWorkers::ValidateTagWorker.perform_async @container.to_global_id.to_s
		redirect_to "/admin/container_images/#{@container.id}", notice: "Validation will be performed shortly."
	end

end
