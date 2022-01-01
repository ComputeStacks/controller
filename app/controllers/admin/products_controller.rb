class Admin::ProductsController < Admin::ApplicationController

  before_action :load_product, only: [:show, :edit, :update, :destroy]

  def index
    @packages = Product.packages.sorted
    @products = Product.where.not(kind: 'package').sorted
  end

  def show
    redirect_to "#{@base_url}/edit"
  end

  def new
    @product = Product.new
  end

  def edit; end

  def create
    @product = Product.new(product_params)
    @product.current_user = current_user
    if @product.save
      if @product.kind == "package"
        @package = @product.build_package
        @package.cpu = 1
        @package.memory = 1024
        @package.bandwidth = 1024
        @package.storage = 10
        @package.local_disk = 10
        if @package.save
          redirect_to "/admin/products/#{@product.id}/billing_packages/#{@package.id}/edit"
        else
          render template: 'admin/products/billing_packages/new'
        end
      else
        redirect_to "/admin/products", notice: 'Product created.'
      end
    else
      render template: 'admin/products/new'
    end
  end

  def update
    if @product.update(product_params)
      redirect_to "/admin/products", notice: 'Product updated.'
    else
      render template: 'admin/products/edit'
    end
  end

  def destroy
    if @product.subscription_products.empty? && @product.destroy
      flash[:notice] = 'Product deleted'
    elsif !@product.subscription_products.empty?
      flash[:alert] = "Error! This product is being used by subscriptions."
    else
      flash[:alert] = "Error! #{@product.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/products"
  end

  private

  def product_params
    params.require(:product).permit(:label, :kind, :unit, :unit_type, :external_id, :resource_kind, :group)
  end

  def load_product
    @product = Product.find_by(id: params[:id])
    if @product.nil?
      redirect_to "/admin/products", alert: 'Unknown Product.'
      return false
    end
    @product.current_user = current_user
    @base_url = "/admin/products/#{@product.id}-#{@product.name.parameterize}"
  end

end
