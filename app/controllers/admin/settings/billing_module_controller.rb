class Admin::Settings::BillingModuleController < Admin::ApplicationController

  def index
    @active = Setting.billing_module_connected?
    render template: 'admin/settings/billing_module_status', layout: false
  end

end
