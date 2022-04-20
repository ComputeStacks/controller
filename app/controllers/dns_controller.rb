class DnsController < AuthController

  before_action :load_vars, except: [:index, :create, :new]
  before_action :check_permission
  before_action :load_dns_driver, except: [:index]
  before_action :require_administer, only: :destroy

  def index
    @zones = Dns::Zone.find_all_for(current_user)
  end

  def show
    if @zone.provision_driver
      @zone_client = @zone.state_load!
      @dnsec = @zone_client.sec_params
      if @zone_client.records.nil? || @zone_client.records['NS'].empty?
        redirect_to "/dns", alert: "Error loading Zone File."
        return false
      end
    end
  rescue
    redirect_to "/dns", alert: "Error connecting to DNS Server."
  end

  def new
    # using current_user.dns_zones.new would save the record!!
    @zone = Dns::Zone.new
  end

  def create
    @zone = Dns::Zone.new(zone_params)
    @zone.current_user = current_user
    @zone.user = current_user
    @zone.run_module_create = true
    @zone.provision_driver = @dns_driver
    if @zone.valid? && @zone.save && @zone.errors.full_messages.empty?
      redirect_to "/dns/#{@zone.id}-#{@zone.name.parameterize}", notice: "#{@zone.name} created."
    else
      render template: 'dns/new'
    end
  end

  def edit; end

  def update
    if @zone.update(zone_params)
      redirect_to "/dns/#{@zone.id}-#{@zone.name.parameterize}", notice: "#{@zone.name} updated."
    else
      render template: 'dns/edit'
    end
  end

  def destroy
    response = @zone.module_delete!
    if response['success']
      flash[:notice] = I18n.t('crud.deleted', resource: 'DNS Zone')
    else
      flash[:alert] = "Error! #{response['message']}"
    end
    redirect_to "/dns"
  end

  private

  def check_permission
    unless Feature.check('dns', current_user)
      render template: "layouts/shared/disabled"
      return false
    end
  end

  def zone_params
    params.require(:dns_zone).permit( :name, :commit_changes, :revert_changes, :soa_email )
  end

  def load_vars
    @zone = Dns::Zone.find_for current_user, id: params[:id]
    if @zone.nil?
      redirect_to "/dns", alert: 'Zone not found.'
      return false
    end
    if @zone.provision_driver.nil?
      redirect_to "/dns", alert: 'Missing Zone Connection Info.'
      return false
    end
    @zone.current_user = current_user
  end

  def load_dns_driver
    @dns_driver = ProductModule.find_by(name: 'dns')&.default_driver
    if @dns_driver.nil?
      return redirect_to("/dns", alert: "DNS not configured.")
    end
    @provision_drivers = ProvisionDriver.dns_drivers
  end

  def require_administer
    unless @zone.can_administer? current_user
      redirect_to "/dns/#{@zone.id}", alert: "Permission denied"
    end
  end

end
