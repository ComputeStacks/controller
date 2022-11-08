class Api::Admin::ContainerImages::ImageVariants::BaseController < Api::Admin::ContainerImages::BaseController

  before_action :find_variant

  private

  def find_variant
    @variant = @image.image_variants.find params[:image_variant_id]
    @variant.current_user = current_user
  end

end
