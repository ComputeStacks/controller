class Admin::Products::BillingPackagesController < Admin::ApplicationController

  before_action :load_product
  before_action :load_package, only: [:edit, :show, :update]

  def show
    redirect_to "#{@base_url}/#{@product.id}/billing_packages/#{@package.id}/edit"
  end

  def new
    @package = @product.build_package
  end

  def edit; end

  def create
    @package = @product.build_package(package_params)
    if @package.save
      redirect_to @base_url, notice: 'Package Created'
    else
      render template: 'admin/products/billing_packages/new'
    end
  end

  def update
    if @package.update(package_params)
      redirect_to @base_url, notice: 'Package Updated'
    else
      render template: 'admin/products/billing_packages/edit'
    end
  end

  def destroy
    redirect_to @base_url, alert: "Delete the entire product, not just the package"
  end

  private

  def package_params
    params.require(:billing_package).permit(:cpu, :memory, :storage, :bandwidth, :backup, :local_disk, :memory_swap, :memory_swappiness)
  end

  def load_product
    @product = Product.find_by(id: params[:product_id])
    if @product.nil?
      redirect_to "/admin/products", alert: 'Unknown Product'
      return false
    end
    @base_url = "/admin/products"
  end

  def load_package
    @package = @product.package # Only 1 package per product.
    if @package.nil?
      redirect_to @base_url, alert: 'Unknown Package'
      return false
    end
  end

end
