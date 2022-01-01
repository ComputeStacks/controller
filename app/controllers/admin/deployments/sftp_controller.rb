class Admin::Deployments::SftpController < Admin::Deployments::BaseController

  def index
    @sftp_containers = @deployment.sftp_containers.sorted
    return render(template: "admin/deployments/sftp/index", layout: false) if params[:js]
  end

  # Trigger SFTP re-generation for a project
  def create
    audit = Audit.create_from_object! @deployment, 'updated', request.remote_ip, current_user
    event = EventLog.create!(
      locale: 'deployment.sftp_init',
      locale_keys: { project: @deployment.name },
      event_code: '85c94efd24eda517',
      status: 'pending',
      audit: audit
    )
    event.deployments << @deployment
    ProjectWorkers::SftpInitWorker.perform_async @deployment.to_global_id.uri, event.to_global_id.uri
    redirect_to "/admin/deployments/#{@deployment.id}", notice: I18n.t('crud.queued_plural', resource: 'Project SSH containers')
  end

end
