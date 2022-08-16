class Deployments::SftpController < Deployments::BaseController

  before_action :find_sftp, only: %i[show update]

  def show
    if request.xhr?
      render plain: @sftp.password
    end
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
    ProjectWorkers::SftpInitWorker.perform_async @deployment.to_global_id.to_s, event.to_global_id.to_s
    redirect_to "/deployments/#{@deployment.token}", notice: I18n.t('crud.queued_plural', resource: 'Project SSH containers')
  end

  # Toggle PW Auth
  def update
    @sftp.current_audit = Audit.create_from_object! @sftp, 'updated', request.remote_ip, current_user
    @sftp.toggle_pw_auth!
    if request.xhr?
      head :created
    else
      redirect_back fallback_location: "/deployments/#{@deployment.token}", notice: "Password Auth has been updated"
    end
  end

  private

  def find_sftp
    @sftp = @deployment.sftp_containers.find_by(id: params[:id])
    return(redirect_to("/deployments/#{@deployment.token}", alert: "Unknown container")) if @sftp.nil?
  end

end
