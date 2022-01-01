class Admin::DnsController < Admin::ApplicationController

  before_action :load_vars, except: [:index, :create, :new]
  before_action :load_users, only: %w(new edit update create)
  before_action :load_dns_driver

  def index
    if params[:filter].nil? || !%w(User System Unlinked).include?(params[:filter])
      @zone_filter = nil
      @zones = ::Dns::Zone.paginate(page: params[:page], per_page: 30).order(:name)
    else
      @zone_filter = params[:filter]
      case @zone_filter
      when 'User'
        @zones = ::Dns::Zone.where('user_id is not null').paginate(page: params[:page], per_page: 30).order(:name)
      when 'System'
        @zones = ::Dns::Zone.where('user_id is null').paginate(page: params[:page], per_page: 30).order(:name)
      when 'Unlinked'
        @zones = @dns_driver.module_settings.allow_unknown_zones? ? ::Dns::Zone.load_all : []
      end
    end
  end

  def new
    @zone = ::Dns::Zone.new
    @zone.run_module_create = true
  end

  def edit
    if @zone.provision_driver
      zone_client = @zone.state_load!
      @allow_module_create = zone_client.records['NS'].empty?
    else
      @allow_module_create = true
    end
  end

  def update

    if @zone.update(zone_params)
      redirect_to "/admin/dns/#{@zone.id}-#{@zone.name.parameterize}", notice: "#{@zone.name} updated."
    else
      if @zone.provision_driver
        zone_client = @zone.state_load!
        @allow_module_create = zone_client.records['NS'].empty?
      else
        @allow_module_create = true
      end
      render template: 'admin/dns/edit'
    end

  end

  def show
    if @zone.provision_driver
      @zone_client = @zone.state_load!
      @dnsec = @zone_client.sec_params
      if @zone_client.records.nil?
        redirect_to "/admin/dns", alert: "Error loading Zone File."
        return false
      end
      if @zone_client.records['NS'].empty?
        redirect_to "/admin/dns/#{@zone.id}/edit", alert: "This zone does not appear to exist on the DNS server. Please update the settings."
        return false
      end
    end
  rescue
    redirect_to "/admin/dns", alert: "Error connecting to DNS Server."
  end

  def create
    @zone = ::Dns::Zone.new(zone_params)
    @zone.current_user = current_user
    @zone.skip_provision_driver = true if zone_params[:provision_driver_id].blank?
    if @zone.valid? && @zone.save && @zone.errors.full_messages.empty?
      redirect_to "/admin/dns/#{@zone.id}-#{@zone.name.parameterize}", notice: "#{@zone.name} created."
    else
      render template: 'admin/dns/new'
    end
  end

  def destroy
    response = @zone.module_delete!
    if response['success']
      flash[:notice] = "Zone Deleted."
    else
      flash[:alert] = "Error! #{response['message']}"
    end
    redirect_to "/admin/dns"
  end

  private

  def zone_params
    params.require(:dns_zone).permit(
        :name, :provider_ref, :provision_driver_id,
        :user_id, :run_module_create, :commit_changes,
        :revert_changes, :soa_email
    )
  end

  def load_vars
    @zone = ::Dns::Zone.find_by(id: params[:id])
    if @zone.nil?
      redirect_to "/admin/dns", alert: 'Zone not found.'
      return false
    end
    @zone.current_user = current_user
  end

  def load_dns_driver
    @dns_driver = ProductModule.find_by(name: 'dns')&.default_driver
    if @dns_driver.nil?
      redirect_to "/admin/dashboard", alert: "DNS not configured."
      return false
    end
    @provision_drivers = ProvisionDriver.dns_drivers
  end

  def load_users
    @users = User.by_last_name
  end

end
