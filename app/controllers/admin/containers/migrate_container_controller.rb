class Admin::Containers::MigrateContainerController < Admin::Containers::BaseController

  before_action :check_permission

  def index; end

  def create
    audit = Audit.create_from_object!(@container, 'updated', request.remote_ip, current_user)
    event = EventLog.create!(
      locale: 'container.migrating',
      locale_keys: { 'container' => @container.name },
      event_code: '4c7a96039fac57d9',
      status: 'pending',
      audit: audit
    )
    event.containers << @container
    event.deployments << @container.deployment
    event.container_services << @container.service
    ContainerWorkers::MigrateContainerWorker.perform_async @container.global_id, event.global_id
    redirect_to "/admin/containers/#{@container.id}", notice: I18n.t('containers.high_availability.migration.success')
  end

  private

  def check_permission
    unless @container.can_migrate?
      redirect_to "/admin/containers/#{@container.id}", alert: I18n.t('containers.high_availability.migration.controller_error')
      return false
    end
  end

end
