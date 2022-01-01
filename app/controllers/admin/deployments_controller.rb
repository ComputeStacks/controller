class Admin::DeploymentsController < Admin::ApplicationController

  before_action :load_deployment, only: [:show, :edit, :update, :destroy]

  def index
    deployments = Deployment
    deployments = case params[:user].to_i
                  when 0
                    deployments
                  else
                    @user = User.find_by(id: params[:user])
                    @user.nil? ? deployments : @user.deployments
                  end
    deployments = case params[:region].to_i
                  when 0
                    deployments
                  else
                    region = Region.find_by(id: params[:region])
                    region.nil? ? deployments : deployments.where(regions: {id: region.id}).joins(:regions).distinct
                  end
    if params[:image].is_a?(Array)
      image_ids = params[:image].map {|i| i.to_i}
      deployments = deployments.where("container_images.id IN (?)", image_ids).joins(:container_images).distinct
    end
    if params[:disk_usage] && params[:disk_usage].to_i > 0
      disk_size_ids = Deployment.project_ids_by_disk_usage params[:disk_usage].to_i
      disk_size_ids = disk_size_ids.empty? ? 0 : disk_size_ids.join(', ')
      deployments = deployments.where( Arel.sql %Q( id IN (#{disk_size_ids}) ) )
    end
    unless params[:created_between].blank?
      begin
        stime = Time.parse(params[:created_between].split("-").first.strip).utc
        etime = Time.parse(params[:created_between].split("-").last.strip).utc
        deployments = deployments.where( Arel.sql %Q( created_at BETWEEN '#{stime}' AND '#{etime}' ) )
      rescue
        flash[:alert] = "#{params[:created_between]} is an invalid date range"
        params[:created_between] = ""
      end
    end
    if params[:package].is_a?(Array)
      package_ids = params[:package].map { |i| i.to_i }.join(', ')
      deployments = deployments.joins(subscriptions: { subscription_products: :product }).where( Arel.sql( %Q(subscription_products.product_id IN (#{package_ids})) ) ).distinct
    end
    @deployments = deployments.sorted.paginate page: params[:page], per_page: 30
  end

  def show; end

  def edit; end

  def update
    audit = Audit.create_from_object!(@deployment, 'updated', request.remote_ip, current_user)
    @deployment.current_audit = audit
    if @deployment.update(deployment_params)
      redirect_to "/admin/deployments/#{@deployment.id}", success: "Successfully updated deployment."
      return false
    end
    if @deployment.errors
      flash[:alert] = "#{@deployment.errors.full_messages.join(' ')}"
    end
    render template: 'admin/deployments/edit'
  end

  def destroy
    audit = Audit.create_from_object!(@deployment, 'deleted', request.remote_ip, current_user)
    event = EventLog.create!(
      locale: 'deployment.trash',
      locale_keys: { project: @deployment.name },
      event_code: '20cd984da4da8963',
      audit: audit,
      status: 'pending'
    )
    @deployment.mark_trashed!
    event.deployments << @deployment
    ProjectWorkers::TrashProjectWorker.perform_async @deployment.to_global_id.uri, event.to_global_id.uri
    redirect_to "/admin/deployments", notice: 'Project queued for destruction.'
  end

  private

  def deployment_params
    params.require(:deployment).permit(:name, :user_id, :skip_ssh)
  end

  def load_deployment
    @deployment = Deployment.find_by(id: params[:id])
    if @deployment.nil?
      redirect_to "/admin/dashboard"
      return false
    end
    @deployment.current_user = current_user
  end

end
