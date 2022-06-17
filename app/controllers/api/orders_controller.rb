##
# Orders API
class Api::OrdersController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :order_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :order_write }, only: %i[update create destroy], unless: :current_user

  before_action :load_order, only: %i[ show ]

  ##
  # List all orders
  #
  # `GET /api/orders`
  #
  # **OAuth AuthorizationRequired**: `order_read`
  #
  # * `orders`: Array
  #     * `id`: UUID
  #     * `status`: `String<open,pending,awaiting_payment,processing,cancelled,failed,completed`
  #     * `project`: Object
  #         * `id`: Integer
  #         * `name`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @orders = paginate current_user.orders
  end

  ##
  # Get a single order
  #
  # `GET /api/orders/{id}`
  #
  # **OAuth AuthorizationRequired**: `order_read`
  #
  # * `orders`: Object
  #     * `id`: UUID
  #     * `status`: `String<open,pending,awaiting_payment,processing,cancelled,failed,completed`
  #     * `project`: Object
  #         * `id`: Integer
  #         * `name`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show; end

  ##
  # Create a new order
  #
  # `POST /api/orders`
  #
  # **OAuth AuthorizationRequired**: `order_write`
  #
  # Volumes:
  # You have the option to override the volume settings defined in the image template by passing various options:
  #
  # * Omitting `volumes` completely, or by passing an empty array, will keep the defaults defined in the image.
  # * Passing a volume `csrn` will allow you to modify the mount options defined in the image:
  #     * `action: clone` -- Clone the source volume. This will take a snapshot, and restore that to the newly created volume.
  #     * `action: mount` -- This will mount the source volume, and you have the option to mount it in readonly mode. Note, that this option also has the effect of forcing this container to be provisioned on the same node as the source volume (unless using NFS-backed volume storage).
  #
  # * `order`: Object
  #     * `project_name`: String
  #     * `skip_ssh`: Boolean
  #     * `location_id`: Integer
  #     * `project_id`: Integer | Only if adding to existing project
  #     * `containers`: Array
  #         * `image_id`: Integer
  #         * `domains`: Array<String> | provide an optional list of domains you want added after the order is provisioned.
  #         * `resources`: Object
  #             * `package_id`: Integer
  #         * `params`: Array
  #             * `key`: String
  #             * `value`: String
  #         * `volumes`: Array | You may omit volumes, but you may not add volumes that don't exist in the image.
  #             * `csrn`: String | resource name of volume param from image
  #             * `action`: String<create,clone,mount,skip> | Volumes not included will default to create.
  #             * `source`: String | csrn of existing volume
  #             * `snapshot`: String | ID of specific snapshot to restore
  #             * `mount_ro`: Bool | Defaults to false, which is read-write.
  #
  def create
    audit = Audit.create!(
      user: current_user,
      ip_addr: request.remote_ip,
      event: 'created'
    )
    build_order = BuildOrderService.new(audit, new_deployment_params)
    build_order.process_order = true

    msg = if build_order.perform
            {
              order: {
                id: build_order.order.id,
                redirect_url: build_order.redirect_url,
                load_balancer_ip: build_order.order.data.dig('load_balancer_ip')
              }
            }
          else
            {
              errors: build_order.errors
            }
          end

    respond_to do |format|
      format.json {render json: msg, status: (msg[:errors] ? :unprocessable_entity : :created)}
      format.xml {render xml: msg, status: (msg[:errors] ? :unprocessable_entity : :created)}
    end
  rescue => e
    Rails.logger.warn(e) unless Rails.env.production?
    return api_fatal_error(e, 'e209b330586af9f2')
  end

  private

  ##
  # New Order Params
  #
  # Deprecated:
  #   * containers[:container_image_id] (replaced by: image_id)
  #   * containers[:product_id] (replaced by: resources[:product_id])
  #   * containers[:package_id] (replaced by: resources[:product_id])
  #   * containers[:resources][:package_id] (replaced by: resources[:product_id])
  #
  def new_deployment_params
    params.require(:order).permit(
      :project_name, :skip_ssh, :location_id, :project_id, containers: [
      :image_id, :name, :container_image_id, :product_id, :package_id,
      resources: [
        :product_id, :package_id
      ],
      params: [:key, :value],
      domains: [],
      volumes: [
        :csrn, :action, :source, :mount_ro, :snapshot
      ]
    ]
    )
  end

  ##
  # Load the order
  def load_order # :doc:
    @order = current_user.orders.find_by(id: params[:id])
    return api_obj_missing if @order.nil?
  end

end
