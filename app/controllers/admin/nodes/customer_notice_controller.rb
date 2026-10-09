##
# The node's customer notice on its edit page: the message customers see while the node
# is in maintenance or offline. Every change goes through NodeServices::CustomerNoticeService,
# which refuses to set one while the node is online.
class Admin::Nodes::CustomerNoticeController < Admin::Nodes::BaseController
  # Set (or, with a blank notice, clear) the notice.
  def update
    apply params[:customer_notice]
  end

  def destroy
    apply nil
  end

  private

  def apply(text)
    service = NodeServices::CustomerNoticeService.new(
      @node,
      notice: text,
      actor: current_user,
      remote_ip: request.remote_ip
    )
    if service.perform
      notice = @node.customer_notice.present? ? "Customer notice set for #{@node.label}." : "Customer notice cleared for #{@node.label}."
      redirect_to edit_path, notice: notice
    else
      redirect_to edit_path, alert: service.errors.join(" ")
    end
  end

  def edit_path
    "/admin/nodes/#{@node.id}/edit"
  end
end
