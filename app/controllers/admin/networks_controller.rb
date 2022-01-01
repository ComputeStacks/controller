class Admin::NetworksController < Admin::ApplicationController

  before_action :find_network, except: %w(index new create)

  def index
    @networks = Network.sorted
  end

  def show
    @addr = @network.addresses.paginate(page: params[:page], per_page: 30)
  end

  def new
    @network = Network.new
    @network.cidr = "192.168.0.0/24"
  end

  def edit; end

  def update
    if network_params[:cidr].split(':').count > 1
      params[:node].delete(:cidr) # Just don't update it
    end
    if @network.update(network_params)
      redirect_to "/admin/networks", notice: "#{@network.label} successfully updated."
    else
      render template: "admin/networks/edit"
    end
  end

  def create
    if network_params[:cidr].split(':').count > 1
      redirect_to '/admin/networks/new', alert: "Network must be IPv4."
      return false
    end
    @network = Network.new(network_params)
    @network.current_user = current_user
    if @network.valid? && @network.save
      redirect_to "/admin/networks", notice: "#{@network.label} successfully updated."
    else
      render template: "admin/networks/new"
    end
  end

  def destroy
    if @network.destroy
      redirect_to "/admin/networks", notice: "#{@network.label} successfully deleted."
    else
      redirect_to "/admin/networks", alert: "Failed to delete #{@network.label}."
    end
  end

  private

  def network_params
    params.require(:network).permit(:cidr, :is_public, :name, :label, {region_ids: []})
  end

  def find_network
    @network = Network.find_by(id: params[:id])
    if @network.nil?
      redirect_to "/admin/networks", alert: "Network not found."
      return false
    end
    @network.current_user = current_user
  end
end
