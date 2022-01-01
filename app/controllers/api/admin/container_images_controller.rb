##
# # Container Images
class Api::Admin::ContainerImagesController < Api::Admin::ApplicationController

	##
	# List all images
	#
	# `GET /api/admin/container_images`
	#
	# null user == public (system) image.
	#
	def index
		@container_images = paginate ContainerImage.all.sorted
		respond_to :json, :xml
	end

	##
	# View an image
	#
	# `GET /api/admin/container_images/{id}`
	#
	# null user == public (system) image.
	#
	def show
		@container_image = ContainerImage.find_by id: params[:id]
		return api_obj_missing if @container_image.nil?
		respond_to :json, :xml
	end

end
