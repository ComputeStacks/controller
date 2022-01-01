class Admin::Networks::IpAddressesController < Admin::ApplicationController

  before_action :load_network
  before_action :load_ip_address

  def update
    # Release IP
    # not implemented yet.
    redirect_to "/admin/networks/#{@network.id}"
  end

  def destroy
    # not implemented yet.
    redirect_to "/admin/networks/#{@network.id}"
  end

  private

  def load_network
    @network = Network.find_by(id: params[:network_id])
    if @network.nil?
      redirect_to "/admin/networks", alert: "Unknown network."
      return false
    end
  end

  def load_ip_address
    @addr = Network::Cidr.find_by(params[:id])
    if @addr.nil?
      redirect_to "/admin/networks/#{@network.id}", alert: "Unknown IP Address"
      return false
    end
  end

end