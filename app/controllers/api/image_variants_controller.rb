##
# Image Variant Lookup
# 
# Helper controller to find a container image when all you know is a variant id.
# 
# To perform actions on an image variant, @see Api::ContainerImages::ImageVariantsController
#
class Api::ImageVariantsController < Api::ApplicationController
  
  api_scope show: :images_read

  ##
  # View an image by it's variant ID
  # 
  # `GET /api/image_variants/:id`
  # 
  # **OAuth Authorization Required**: `images_read`
  # 
  # @see Api::ContainerImagesController#index
  #
  def show
    variant = ContainerImage::ImageVariant.find_by id: params[:id]
    return api_obj_missing if variant.nil?

    @container_image = variant.container_image
    return api_obj_missing unless @container_image.can_view?(current_user)
    
    respond_to do |format|
      format.any(:json, :xml) { render template: "api/container_images/show" }
    end
  end

end