class Admin::AuditController < Admin::ApplicationController

  before_action :load_audit, only: :show

  def index
    @events = Audit.where.not(rel_model: nil).sorted.paginate page: params[:page], per_page: 40
  end

  def show; end

  private

  def load_audit
    @audit = Audit.find_by(id: params[:id])
    return redirect_to("/admin/dashboard", alert: "Not found.") if @audit.nil?
  end

end
