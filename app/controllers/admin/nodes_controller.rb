class Admin::NodesController < Admin::ApplicationController

  before_action :load_node, except: %w(index new create)

  def index
    @nodes = Node.sorted
  end

  def show
    if request.xhr?
      render template: "admin/nodes/index/metrics_overview", layout: false
    else
      redirect_to "/admin/regions/#{@node.region.id}"
    end
  end

  def new
    @node = Node.new
    @node.port_begin = 10000
    @node.port_end = 50000
    @node.primary_ip = "10.0.0.10"
    @node.public_ip = "10.0.0.10"
    @node.active = true
  end

  def edit; end

  def update
    maint_mode = ActiveRecord::Type::Boolean.new.cast params[:node][:maintenance]
    unless maint_mode == @node.maintenance
      audit = Audit.create_from_object!(@node, 'updated', request.remote_ip, current_user)
      if maint_mode
        @node.update(
          maintenance: true,
          maintenance_updated: Time.now
        )
        if @node.region.has_clustered_storage?
          NodeWorkers::EvacuateNodeWorker.perform_async @node.global_id, audit.global_id
        end
      else
        @node.update(
          maintenance: false,
          maintenance_updated: Time.now,
          job_status: 'idle'
        )
      end
    end
    if @node.update(node_params)
      redirect_to "/admin/regions/#{@node.region_id}", notice: "#{@node.label} successfully updated."
    else
      render template: "admin/nodes/edit"
    end
  end

  def create
    @node = Node.new(node_params)
    @node.current_user = current_user
    if @node.valid? && @node.save
      redirect_to "/admin/regions/#{@node.region_id}", notice: "#{@node.label} successfully created."
    else
      render template: "admin/nodes/new"
    end
  end

  def destroy
    if @node.destroy
      redirect_to "/admin/regions/#{@node.region_id}", notice: "#{@node.label} successfully deleted."
    else
      redirect_to "/admin/regions/#{@node.region_id}", alert: "#{@node.errors.full_messages.join(', ')}"
    end
  end

  private

  def node_params
    params.require(:node).permit(
        :label, :hostname, :primary_ip, :active,
        :public_ip, :region_id, :port_begin, :port_end,
        :volume_device, :block_write_bps, :block_read_bps,
        :block_write_iops, :block_read_iops
    )
  end

  def load_node
    @node = Node.find_by(id: params[:id])
    if @node.nil?
      redirect_to "/admin/nodes", alert: "Node not found."
      return false
    end
    @region = @node.region
    @node.current_user = current_user
  end

end
