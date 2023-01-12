##
# # Product
class Api::Admin::ProductsController < Api::Admin::ApplicationController

  before_action :load_product, except: %i[ index create ]

  ##
  # List Products
  #
  # `GET /api/admin/products`
  #
  # * `products`: Array
  #     * `id`: Integer
  #     * `label`: String
  #     * `kind`: String `<package, image, resource, addon>`
  #     * `resource_kind`: String - backup,bandwidth,cpu,ipaddr,memory,storage,local_disk (only for non-packages)
  #     * `unit`: Integer - (only for non-packages)
  #     * `unit_type`: String - (only for non-packages)
  #     * `group`: String
  #     * `package`: Object
  #         * `id`: Integer
  #         * `cpu`: Decimal - CPU Cores (supports fractional cores as decimal)
  #         * `memory`: String - MB
  #         * `memory_swap`: Integer - Amount of memory (MB) allowed to swap to disk.
  #         * `memory_swappiness`: Integer between 1 and 100 (default 60).
  #         * `bandwidth`: Integer - Included bandwidth (GB)
  #         * `storage`: Integer - Volume Storage (GB)
  #         * `local_disk`: Integer - Temporary / Local Disk storage (GB)
  #         * `backup`: Integer - Included backup storage (GB)
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def index
    @products = paginate Product.all.order(:created_at)
    respond_to :json, :xml
  end

  ##
  # View Product
  #
  # `GET /api/admin/products/{id}`
  #
  # * `product`: Object
  #     * `id`: Integer
  #     * `label`: String
  #     * `kind`: String `<package, image, resource, addon>`
  #     * `resource_kind`: String - backup,bandwidth,cpu,ipaddr,memory,storage,local_disk (only for non-packages)
  #     * `unit`: Integer - (only for non-packages)
  #     * `unit_type`: String - (only for non-packages)
  #     * `group`: String
  #     * `package`: Object
  #         * `id`: Integer
  #         * `cpu`: Decimal - CPU Cores (supports fractional cores as decimal)
  #         * `memory`: String - MB
  #         * `memory_swap`: Integer - Amount of memory (MB) allowed to swap to disk.
  #         * `memory_swappiness`: Integer between 1 and 100 (default 60).
  #         * `bandwidth`: Integer - Included bandwidth (GB)
  #         * `storage`: Integer - Volume Storage (GB)
  #         * `local_disk`: Integer - Temporary / Local Disk storage (GB)
  #         * `backup`: Integer - Included backup storage (GB)
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def show
    respond_to :json, :xml
  end

  ##
  # Update Product
  #
  # `PATCH /api/admin/products/{id}`
  #
  # Be aware that updating a package through this will completly delete the package, and re-create it with the values you provide. Be sure to supply _all_ values for the package. To only update the product, and not the package, omit the `package_attributes` object.
  #
  # * `product`: Object
  #     * `label`: String
  #     * `kind`: String `<package, image, resource, addon>`
  #     * `resource_kind`: String - backup,bandwidth,cpu,ipaddr,memory,storage,local_disk (only for non-packages)
  #     * `unit`: Integer - (only for non-packages)
  #     * `unit_type`: String - (only for non-packages)
  #     * `group`: String (optional)
  #     * `package_attributes`: Object
  #         * `cpu`: Decimal - CPU Cores (supports fractional cores as decimal)
  #         * `memory`: String - MB
  #         * `memory_swap`: Integer - Amount of memory (MB) allowed to swap to disk.
  #         * `memory_swappiness`: Integer between 1 and 100 (default 60).
  #         * `bandwidth`: Integer - Included bandwidth (GB)
  #         * `storage`: Integer - Volume Storage (GB)
  #         * `local_disk`: Integer - Temporary / Local Disk storage (GB)
  #         * `backup`: Integer - Included backup storage (GB)

  def update
    return api_obj_error(@product.errors.full_messages) unless @product.update(product_params)
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :ok }
    end
  end

  ##
  # Create Product
  #
  # `POST /api/admin/products`
  #
  # Be sure to add products to billing plans and create price rules.
  #
  # * `product`: Object
  #     * `label`: String
  #     * `kind`: String `<package, image, resource, addon>`
  #     * `resource_kind`: String - backup,bandwidth,cpu,ipaddr,memory,storage,local_disk (only for non-packages)
  #     * `unit`: Integer - (only for non-packages)
  #     * `unit_type`: String - (only for non-packages)
  #     * `group`: String (optional)
  #     * `package_attributes`: Object
  #         * `cpu`: Decimal - CPU Cores (supports fractional cores as decimal)
  #         * `memory`: String - MB
  #         * `memory_swap`: Integer - Amount of memory (MB) allowed to swap to disk.
  #         * `memory_swappiness`: Integer between 1 and 100 (default 60).
  #         * `bandwidth`: Integer - Included bandwidth (GB)
  #         * `storage`: Integer - Volume Storage (GB)
  #         * `local_disk`: Integer - Temporary / Local Disk storage (GB)
  #         * `backup`: Integer - Included backup storage (GB)

  def create
    @product = Product.new(product_params)
    @product.current_user = current_user
    return api_obj_error(@product.errors.full_messages) unless @product.save
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :created }
    end
  end

  ##
  # Delete Product
  #
  # `DELETE /api/admin/products/{id}`

  def destroy
    return api_obj_error(@product.errors.full_messages) unless @product.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :no_content }
    end
  end

  private

  def load_product
    @product = Product.find_by(id: params[:id])
    return api_obj_missing if @product.nil?
    @product.current_user = current_user
  end

  def product_params
    params.require(:product).permit(
      :label, :kind, :resource_kind, :unit, :unit_type, :group,
      package_attributes: [
        :cpu, :memory, :memory_swap, :memory_swappiness, :bandwidth, :storage, :local_disk, :backup
      ]
    )
  end

end
