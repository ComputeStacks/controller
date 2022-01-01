class Api::Admin::ContainerRegistry::BaseController < Api::Admin::ApplicationController

  before_action :find_registry

  private

  def find_registry
    @registry = ContainerRegistry.find params[:container_registry_id]
    @registry.current_user = current_user
  end

end
