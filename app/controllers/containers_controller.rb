class ContainersController < AuthController
  include RescueResponder

  before_action :find_container

  def show
    @settings = @service.setting_params
  end

  private

  def find_container
    @container = Deployment::Container.find_for current_user, id: params[:id]
    return redirect_to('/deployments', alert: I18n.t('crud.unknown', resource: I18n.t('obj.container'))) if @container.nil?
    @service = @container.service
    @deployment = @container.deployment
    if @service.nil?
      return redirect_to('/deployments', alert: I18n.t('crud.unknown', resource: I18n.t('obj.container')))
    end
  end

  def not_found_responder
    return redirect_to('/deployments', alert: I18n.t('crud.unknown', resource: I18n.t('obj.container')))
  end

end
