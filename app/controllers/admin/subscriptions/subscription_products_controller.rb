class Admin::Subscriptions::SubscriptionProductsController < Admin::Subscriptions::BaseController

  before_action :find_sub_product, only: %w(show edit update destroy)
  before_action :find_products, except: %w(index destroy)

  def index
    @products = @subscription.subscription_products.order(:created_at)
    render layout: false
  end

  def edit; end


  def update
    if @subscription_product.update(sp_params)
      redirect_to "/admin/subscriptions/#{@subscription.id}"
    else
      render template: "admin/subscriptions/subscription_products/edit"
    end
  end

  def new
    @subscription_product = @subscription.subscription_products.new
  end

  def create
    sp = @subscription.subscription_products.new(sp_params)
    if sp.valid? && sp.save
      redirect_to "/admin/subscriptions/#{@subscription.id}"
    else
      render template: "admin/subscriptions/subscription_products/new"
    end
  end

  def destroy
    if @subscription_product.product&.package && !@subscription.linked.nil?
      return(redirect_to("/admin/subscriptions/#{@subscription.id}", alert: "Unable to remove package while an active service exists. Please cancel that service first."))
    end
    if @subscription_product.destroy
      flash[:notice] = "Product removed from subscription."
    else
      flash[:alert] = @subscription_product.errors.full_messages.join(' ')
    end
    redirect_to "/admin/subscriptions/#{@subscription.id}"
  end

  private

  def find_sub_product
    @subscription_product = @subscription.subscription_products.find_by(id: params[:id])
    if @subscription_product.nil?
      redirect_to "/admin/subscriptions/#{@subscription.id}", alert: 'Unknown Subscription Product'
      return false
    end
  end

  def find_products
    user = @subscription.user
    @products = user.billing_plan.products.order(:label)
  end

  def sp_params
    params.require(:subscription_product).permit(:active, :external_id, :phase_type, :product_id)
  end

end
