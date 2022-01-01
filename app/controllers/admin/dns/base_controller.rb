# Legacy base controller
class Admin::Dns::BaseController < Admin::ApplicationController

  before_action :dns_enabled?
  before_action :load_dns_driver
  before_action :find_zone

  private

  def dns_enabled?
    return if Feature.check('dns', current_user)
    redirect_to('/admin/dashboard', alert: I18n.t('common.feature_disabled', resource: 'DNS'))
  end

  def load_dns_driver
    @dns_driver = ProvisionDriver.dns_drivers.first
    redirect_to("/admin/dashboard", alert: "DNS not configured.") if @dns_driver.nil?
  end

  def find_zone
    @zone = Dns::Zone.find_by id: params[:dn_id]
    if @zone.nil?
      respond_to do |format|
        format.json { head :unauthorized }
        format.xml {  head :unauthorized }
        format.html { redirect_to("/admin/dns", alert: "Unknown zone") }
      end
    end
  end

end
