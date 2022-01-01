class ContainerServices::AutoScaleController < ContainerServices::BaseController

  def edit; end

  def update
    if @service.update(service_params)
      redirect_to container_service_path(@service), success: 'AutoScale Updated'
    else
      render :edit
    end
  end

  private

  def service_params
    params.require(:deployment_container_service).permit(:auto_scale, :auto_scale_horizontal, :auto_scale_max)
  end

end
