class Deployments::OrdersController < AuthController

  before_action :load_order_session

  def index

    @containers = ContainerImage.is_public.non_lbs.available
    @my_containers = ContainerImage.find_all_for(current_user).non_lbs.available

    return fail_and_redirect!(I18n.t('common.feature_disabled', resource: I18n.t('obj.deployment'))) if @containers.empty?

    @all_containers = {
      'apps' => [],
      'db' => [],
      'cache' => [],
      'dev' => [],
      'infra' => [],
      'misc' => []
    }
    @containers.each do |i|
      container_group = case i.role_class
      when 'web'
        'apps'
      when 'database'
        'db'
      when 'cache'
        'cache'
      when 'dev'
        'dev'
      when 'infra'
        'infra'
      else
        'misc'
      end
      @all_containers[container_group] << i
    end
    render template: "deployments/orders/containers"
  end

  # POST orders/containers
  #
  # Action performs:
  # * Add containers from the index page
  # * Set the project name
  def add_containers
    # render plain: @order_data
    # return false
    if order_params[:containers].nil? || order_params[:containers].empty?
      redirect_to "/deployments/orders", alert: I18n.t('orders.projects.errors.missing_app')
      return false
    end
    if session[:deployment_order].nil?
      return fail_and_redirect! I18n.t('orders.projects.errors.missing_data')
    end
    return fail_and_redirect!('Missing order data') if order_params[:containers].nil?

    # Add any dependent containers to their process
    order_params[:containers].each do |i|
      # container = ContainerImage.find_by(id: i.to_i)
      container = ContainerImage.find_for(current_user, {id: i})
      # Sanity Check
      return fail_and_redirect!('Error! Attempting to order unknown container') if container.nil?
      @order_session.add_image container
    end

    @order_session.save
    # Perform after +@order_session.save+ to preserve user input.
    if order_params[:location_id].blank? && @order_session.location.nil?
      redirect_to "/deployments/orders", alert: 'Missing location.'
      return false
    elsif !order_params[:location_id].blank? && @order_session.location.nil?
      loc = Location.find_by(id: order_params[:location_id])
      if loc.nil?
        redirect_to "/deployments/orders", alert: 'Missing location.'
        return false
      end
      @order_session.location = loc
      @order_session.save
    end
    if @order_session.new_project?
      if order_params[:deployment].nil? || order_params[:deployment].blank?
        redirect_to "/deployments/orders", alert: I18n.t('orders.projects.errors.missing_name')
        return false
      end
      @order_session.project.name = order_params[:deployment]
      @order_session.save
    end
    redirect_to "/deployments/orders/containers"
  end

  ##
  # =Container Param & Package Selection
  #
  # renders: +container_params+, +_shared_containers+
  def show
    if params[:id] == "containers"
      if @order_session.images.empty?
        redirect_to "/deployments/orders", alert: "No containers selected!"
        return false
      end
      if @order_session.skip_to_confirmation?
        create
      else
        render :template => "deployments/orders/container_params"
      end
    else
      fail_and_redirect! I18n.t('orders.projects.errors.general_restart')
    end
  end

  # PUT orders/containers
  def update_containers
    packages = order_params[:package].to_h
    packages.each_key do |i|
      if packages["#{i}"].to_i.zero?
        selected_image = @order_session.images.select {|img| img[:container_id] == i.to_i}[0]
        if selected_image && !selected_image[:free] == 'yes'
          redirect_to "/deployments/orders/containers", alert: I18n.t('orders.projects.errors.missing_package')
          return false
        end
      end
    end

    @order_session.images.each do |i|
      i[:params].each_pair do |k,v|
        next if v[:type] == 'password'
        el = order_params[:service][:"container-#{i[:container_id]}-param-#{k}"]
        v[:value] = el unless el.blank?
      end
      p_el = order_params[:package][:"#{i[:container_id]}"].to_i
      i[:package_id] = p_el unless p_el.zero?
    end

    @order_session.save
    create
  end

  # GET orders/cancel
  def cancel
    session.delete(:deployment_order)
    redir = if @order_session.project && !@order_session.new_project?
              "/deployments/#{@order_session.project.token}"
            else
              '/deployments'
            end
    if @order_session
      @order_session.order.destroy if @order_session.order
      @order_session.destroy
    end
    redirect_to redir
  end

  def create
    if @order_session.images.empty?
      return fail_and_redirect!(I18n.t('orders.projects.errors.general_restart'))
    end

    audit = Audit.create!(
      user: current_user,
      ip_addr: request.remote_ip,
      event: @order ? 'updated' : 'created'
    )
    build_order = BuildOrderService.new(audit, @order_session.to_order)
    build_order.process_order = false

    if @order
      build_order.order = @order
      @order.current_audit = audit
    end

    if build_order.perform
      redirect_to "/orders/#{build_order.order&.id}"
    else
      redirect_to @order_session.skip_to_confirmation? ? "/deployments/orders" : "/deployments/orders/containers", alert: build_order.errors.join(' ')
    end

  end

  private

  def order_params
    params.permit(:location_id, :deployment_type, :deployment, containers: [], package: {}, service: {}, image_map: {})
  end

  def load_order_session
    if session[:deployment_order].blank? || session[:deployment_order].is_a?(Hash)
      return fail_and_redirect!("Invalid params") unless action_name == 'index'
      @order_session = OrderSession.new current_user
      session.delete(:deployment_order) # Start fresh!
      session[:deployment_order] = @order_session.id
    else
      @order_session = OrderSession.new(current_user, session[:deployment_order])
    end

    # Check project
    if params[:o] && action_name == 'index'
      project = Deployment.find_for current_user, token: params[:o]
      return fail_and_redirect!("Unknown project") unless project
      @order_session.project = project
      if @order_session.project != project
        return fail_and_redirect!("Project does not match what has been saved")
      end
      @order_session.save
    end

    @locations = if @order_session.new_project?
                   Location.available_for(current_user, 'container')
                 else
                   @order_session.project.available_locations.empty? ? Location.available_for(current_user, 'container') : @order_session.project.available_locations
                 end

    return fail_and_redirect!("There are no locations available") if @locations.empty?

    @deployment = @order_session.new_project? ? nil : @order_session.project
    @project_owner = @order_session.new_project? ? current_user : @order_session.project.user
    @order = @order_session.order
    @region = @order_session.region

  end

  def fail_and_redirect!(msg = nil)
    @order_session.destroy if @order_session
    session.delete(:deployment_order)
    redirect_to("/deployments", alert: msg.nil? ? 'Fatal error' : msg)
  end

end
