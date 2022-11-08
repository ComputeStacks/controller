class Admin::ContainerImages::ImageVariants::BaseController < Admin::ContainerImages::BaseController

  before_action :find_variant

  private

  def find_variant
    @variant = @image.image_variants.find_by id: params[:image_variant_id]
    if @variant.nil?
      redirect_to "/admin/container_images/#{@image.id}", alert: I18n.t('crud.unknown', resource: I18n.t('obj.container'))
      return false
    end
    @variant.current_user = current_user
  end

end
