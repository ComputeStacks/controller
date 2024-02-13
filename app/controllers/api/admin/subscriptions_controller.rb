##
# Subscriptions
class Api::Admin::SubscriptionsController < Api::Admin::ApplicationController

  before_action :load_subscription, except: [:index]

  ##
  # List Subscriptions
  #
  # `GET /api/admin/subscriptions`
  # `GET /api/admin/(users/:user_id)/subscriptions/(filter/:filter)`
  #
  # You can pass `?filter=` with either `active` or `inactive`. Defaults to showing all subscriptions
  #
  # Returns:
  # * `subscriptions`: Array
  #     * `id`: Integer
  #     * `label`: String
  #     * `external_id`: String
  #     * `active`: Boolean
  #     * `user`: Object
  #         * `id`: Integer
  #         * `full_name`: String
  #         * `email`: String
  #         * `external_id`: String
  #         * `labels`: Object

  def index
    if params[:user_id] && !params[:user_id].to_i.zero?
      user = User.find_by(id: params[:user_id])
      return api_obj_missing(["Unknown user."]) if user.nil?
      case params[:filter]
      when 'active'
        @subscriptions = user.subscriptions.where(active: true).order(created_at: :desc)
      when 'inactive'
        @subscriptions = user.subscriptions.where(active: false).order(created_at: :desc)
      else
        @subscriptions = user.subscriptions.all.order(created_at: :desc)
      end
    else
      case params[:filter]
      when 'active'
        @subscriptions = paginate Subscription.where(active: true).order(created_at: :desc)
      when 'inactive'
        @subscriptions = paginate Subscription.where(active: false).order(created_at: :desc)
      else
        @subscriptions = paginate Subscription.all.order(created_at: :desc)
      end
    end
    respond_to :json, :xml
  end

  # #
  # View Subscription
  #
  # `GET /api/admin/subscription/{id}`
  #
  # Returns:
  # * `subscription`: Object
  #     * `id`: Integer
  #     * `label`: String
  #     * `external_id`: String
  #     * `active`: Boolean
  #     * `run_rate`: Decimal
  #     * `subscription_products`: Array
  #         * `id`: Integer
  #         * `external_id`: String
  #         * `active`: Boolean
  #         * `start_on`: DateTime
  #         * `phase_type`: String
  #         * `created_at`: DateTime
  #         * `updated_at`: DateTime
  #         * `product`: Object
  #             * `id`: Integer
  #             * `label`: String
  #             * `resource_kind`: String
  #             * `unit`: String
  #             * `unit_type`: String
  #             * `external_id`: String
  #             * `created_at`: DateTime
  #             * `updated_at`: DateTime
  #             * `package`: Object
  #                 * `id`: Integer
  #                 * `cpu`: Decimal
  #                 * `memory`: Integer
  #                 * `storage`: Integer
  #                 * `bandwidth`: Integer
  #                 * `local_disk`: Integer
  #                 * `memory_swap`: Integer
  #                 * `memory_swappiness`: Integer
  #                 * `backup`: Integer
  #         * `billing_resource`: Object
  #             * `id`: Integer
  #             * `billing_plan_id`: Integer
  #             * `external_id`: String
  #     * `container`: Object
  #         * `id`: Integer
  #         * `name`: String
  #         * `req_state`: String
  #         * `current_state`: String
  #         * `stats`: Object<cpu: decimal, memory: decimal>
  #         * `local_ip`: String
  #         * `public_ip`: String
  #         * `project_id`: Integer
  #         * `container_service_id`
  #         * `project_id`: Integer
  #         * `created_at`: DateTime
  #         * `updated_at`: DateTime
  #         * `links`: Object
  #             * `container_service`: String
  #             * `logs`: String
  #             * `project`: String
  #         * `region`: Object
  #             * `id`: Integer
  #             * `name`: String
  #         * `node`: Object
  #             *  `id`: Integer
  #             * `label`: String
  #             * `hostname`: String
  #             * `primary_ip`: String
  #             * `public_ip`: String
  #     * `user`: Object
  #         * `id`: Integer
  #         * `full_name`: String
  #         * `email`: String
  #         * `external_id`: String
  #         * `labels`: Object

  def show
    respond_to :json, :xml
  end

  ##
  # Update Subscription
  #
  # `PATCH /api/admin/subscriptions/:id`
  #
  # Use this to upgrade or downgrade an existing service.
  #
  # * `container_service`: Object
  #     * `product_id`: The new product id
  #     * `qty`: The _total_ amount of containers you want. For example, if you have 1 container and you want 2, you would set this value to 2.
  #
  # @example Upgrade a product
  #     {
  #       "container_service": {
  #         "product_id": Integer
  #       }
  #     }
  #
  # @example Scale a service up or down
  #     {
  #       "container_service": {
  #         "qty": Integer
  #       }
  #     }
  #
  # Will return a `HTTP 200` if was successful, otherwise you will have a `HTTP 40x` code and a  `{"errors": []}` response.

  # @todo Refactor upgrade procedure.
  # **In use by WHMCS.**
  #
  def update
    if params[:container_service] # upgrade / downgrade service
      pid = params[:container_service][:package_id].blank? ? params[:container_service][:product_id] : params[:container_service][:package_id]
      is_ok = true
      errors = []
      @service = @subscription.container.service
      return api_obj_missing(["Unknown service"]) if @service.nil?
      audit = Audit.create_from_object!(@service, 'updated', request.remote_ip, current_user)
      # New Package
      unless pid.blank?
        if params[:container_service][:external_product]
          product = Product.find_by(external_id: pid)
        else
          product = Product.find_by(id: pid)
        end
        package = product&.package
        return api_obj_missing(["Unknown product"]) if package.nil?
        # Sanity Check. Don't chang it if it already is set to this value.
        if package != @service.package
          unless @subscription.user.billing_plan.product_available?(package.product)
            errors << 'This package is not assigned to your Billing Plan. Please contact support.'
          end
          if errors.empty?
            container_count = @service.containers.count
            event = @service.event_logs.where("locale = ? AND (status = ? OR status = ?)", (container_count.abs == 1 ? 'service.resizing_1' : 'service.resizing'), 'pending', 'running').first
            ContainerServiceWorkers::ResizeServiceWorker.perform_async(
              @service.global_id,
              event.global_id,
              product.package.global_id
            )
            is_ok = true
          else
            is_ok = false
          end
        end
      end
      if is_ok && params[:container_service][:qty] && !params[:container_service][:qty].to_i.zero?
        # Scale!
        event = @service.event_logs.create!(
            locale: 'service.scaling',
            locale_keys: {
                'label' => @service.label,
                'from' => @service.containers.count,
                'to' => params[:container_service][:qty].to_i
            },
            status: 'pending',
            audit: audit,
            event_code: '69e024c123424165'
        )
        event.deployments << @service.deployment if @service.deployment
        region_check = @service.region
        if region_check && !region_check.nodes.empty?
          ContainerServiceWorkers::ScaleServiceWorker.perform_async @service.global_id, event.global_id
        else
          event.update(
                   status: 'failed',
                   state_reason: "Invalid region.",
                   event_code: '099a4ebcdb9f1274'
          )
          errors << 'Invalid Region. Unable to scale containers.'
          is_ok = false
        end
      end
      unless is_ok
        errors = ['Failed to change plan.'] if errors.empty?
        return api_obj_error(errors)
      end
    else
      # Update the service
      return api_obj_error(@subscription.errors.full_messages) unless @subscription.update(subscription_params)
    end
    respond_to do |format|
      format.json { head :no_content }
      format.xml { head :no_content }
    end
  end

  ##
  # Cancel a subscription
  #
  # `DELETE /api/admin/subscriptions/{id}`
  #
  # **Danger!** This will delete all associated services!
  #
  def destroy
    @subscription.cancel!
    respond_to do |format|
      format.any(:json, :xml) { head :no_content }
    end
  end

  private

  def load_subscription
    if params[:find_by_external_id]
      @subscription = Subscription.find_by(external_id: params[:id])
    else
      @subscription = Subscription.find_by(id: params[:id])
    end
    return api_obj_missing if @subscription.nil?
  end

  def subscription_params
    params.require(:subscription).permit(:label, :active, :external_id)
  end

end
