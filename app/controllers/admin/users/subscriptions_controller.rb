class Admin::Users::SubscriptionsController < Admin::Users::ApplicationController

  def index
    @subscriptions = @user.subscriptions.all_active.sorted.limit(15)
    render template: 'admin/users/show/subscriptions', layout: false
  end

end
