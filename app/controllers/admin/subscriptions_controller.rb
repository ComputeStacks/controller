class Admin::SubscriptionsController < Admin::ApplicationController

  before_action :find_subscription, only: %w(show edit update destroy)
  before_action :load_users, only: %w(edit update)

  def index
    subscriptions = Subscription
    if params[:user]
      @user = User.find_by(id: params[:user])
      subscriptions = @user.subscriptions if @user
    end
    subscriptions = case params[:state]
                    when 'inactive'
                      subscriptions.where(active: false)
                    else
                      subscriptions.where(active: true)
                    end
    subscriptions = case params[:product].to_i
                    when 0
                      subscriptions
                    else
                      product = Product.find_by(id: params[:product])
                      if product
                        subscriptions.where(products: {id: product.id}).joins(:products)
                      else
                        subscriptions
                      end
                    end
    @subscriptions = subscriptions.sorted.paginate per_page: 25, page: params[:page]
  end

  def show
    @billing_events = @subscription.billing_events.limit(15)
  end

  def edit

  end

  def update
    if @subscription.update(subscription_params)
      redirect_to action: :show
    else
      render template: 'admin/subscriptions/update'
    end
  end

  def destroy
    if @subscription.linked_obj
      return(redirect_to("/admin/subscriptions/#{@subscription.id}", alert: "Unable to delete subscription while an active service exists. Please cancel that service first."))
    end
    if @subscription.destroy
      flash[:notice] = "Subscription deleted."
    else
      flash[:alert] = @subscription.errors.full_messages.join(" ")
    end
    redirect_to "/admin/subscriptions"
  end

  private

  def find_subscription
    @subscription = Subscription.find_by(id: params[:id])
    if @subscription.nil?
      redirect_to "/admin/subscriptions"
      return false
    end
    @subscription.current_user = current_user
  end

  def load_users
    if @subscription.container
      @users = User.joins(:deployed_containers).order(:fname)
    else
      @users = User.where("2 = 3") # provide an empty record set.
    end
  end

  def subscription_params
    params.require(:subscription).permit(:label, :external_id, :user_id, :active, container: :id)
  end

end
