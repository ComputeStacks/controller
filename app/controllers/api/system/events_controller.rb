class Api::System::EventsController < Api::System::BaseController

  before_action :find_event, except: %w(index create)

  def index
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/event_logs/index' }
    end
  end

  def show
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/event_logs/show' }
    end
  end

  def create
    if event_params[:deployment_ids] && !event_params[:deployment_ids].empty?
      project = Deployment.find_by(id: event_params[:deployment_ids].first)
      if project.nil?
        Rails.logger.warn "Failed to find project: #{event_params[:deployment_ids].first}"
        return respond_to do |format|
          format.json { render json: {errors: ["Unknown project"]}, status: :unprocessable_entity }
          format.xml { render xml: {errors: ["Unknown project"]}, status: :unprocessable_entity }
        end
      end
    end

    # This is how we can pre-create events for backups.
    @event = if event_params[:audit_id]
               audit = Audit.find_by id: event_params[:audit_id]
               if audit
                 audit.event_logs.active.find_by(event_code: event_params[:event_code])
               end
             end

    if @event&.update(existing_event_params)

      @event.perform_callback_reply! if @event.done?

      respond_to do |format|
        format.any(:json, :xml) { render template: 'api/event_logs/show', status: :created }
      end
      return
    end

    @event = EventLog.new(event_params)
    if event_params[:audit_id].blank? || event_params[:audit_id].to_i.zero?
      if @event.deployments.empty? && !@event.volumes.empty?
        audit = Audit.new(
          event: "updated",
          ip_addr: req_ip,
          rel_id: @event.volumes.first.id,
          rel_model: 'Volume'
        )
        if audit.save
          @event.audit = audit
        end
      elsif !@event.deployments.empty?
        audit = Audit.new(
          event: 'updated',
          ip_addr: req_ip,
          rel_id: @event.deployments.first.id,
          rel_model: 'Deployment'
        )
        if audit.save
          @event.audit = audit
        end
      end
    end
    respond_to do |format|
      if @event.save
        format.any(:json, :xml) { render template: 'api/event_logs/show', status: :created }
      else
        format.json { render json: {errors: @event.errors.full_messages}, status: :unprocessable_entity }
        format.xml { render xml: {errors: @event.errors.full_messages}, status: :unprocessable_entity }
      end
    end
  end

  def update

    if @event.update(event_params)
      @event.perform_callback_reply! if @event.done?
    else
      return api_obj_error(@event.errors.full_messages)
    end

    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/event_logs/show' }
    end
  end

  private

  def existing_event_params
    params.require(:event_log).permit(:status)
  end

  def event_params
    params.require(:event_log).permit(
      :audit_id, :locale, :status, :event_code, local_keys: {},
      deployment_ids: [], container_service_ids: [], volume_ids: [],
      event_details_attributes: [:event_code, :data]
    )
  end

  def req_ip
    raw_ip = request.env['HTTP_X_FORWARDED_FOR'].nil? ? request.remote_ip : request.env['HTTP_X_FORWARDED_FOR']
    raw_ip.to_s.split(":ffff:").last
  end

  def find_event
    @event = EventLog.find_by(id: params[:id])
    return api_obj_missing if @event.nil?
  end

end
