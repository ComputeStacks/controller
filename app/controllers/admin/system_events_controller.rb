class Admin::SystemEventsController < Admin::ApplicationController

  rescue_from ActiveRecord::RecordNotFound, with: :back_to_index

  def index
    @events_for = nil
    @events = SystemEvent.all.paginate(:page => params[:page], :per_page => 30).order(updated_at: :desc)
  end

  def show
    @event = SystemEvent.find_by(id: params[:id])
    if @event.nil?
      redirect_to "/admin/system_events", alert: 'Unknown log.'
      return false
    end
  end

  def destroy_all
    SystemEvent.where("created_at < ?", 1.minute.ago).delete_all
    redirect_to "/admin/system_events"
  end

  private

  def back_to_index
    redirect_to "/admin/system_events", alert: "Not found."
  end

end
