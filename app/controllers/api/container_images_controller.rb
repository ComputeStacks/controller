##
# Container Images API
class Api::ContainerImagesController < Api::ApplicationController
  before_action -> { doorkeeper_authorize! :images_write }, only: %i[ update create destroy ], unless: :current_user

  before_action only: %i[ index show ], unless: :current_user do
    doorkeeper_authorize! :public, :images_read
  end

  ##
  # List all images
  #
  # `GET /api/container_images`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # **Optional Filter Parameters**
  # Name | URL Param
  # -----|----------
  # Owned by your user? | `?filter=owned`
  # Is Load Balancer? | `?filter=isLoadBalancer`
  #
  # * `container_images`: Array
  #     * `id`: Integer
  #     * `active`: Boolean | Visible on order form? This does not disable existing containers, nor does it prevent this image from being used in an image collection.
  #     * `is_load_balancer`: Boolean
  #     * `can_scale`: Boolean
  #     * `command`: String | Command execued by container on start
  #     * `container_image_provider_id`: Integer
  #     * `description`: String
  #     * `domains_block_id`: Integer
  #     * `general_block_id`: Integer
  #     * `icon_url`: String
  #     * `image_url`: String
  #     * `is_free`: Boolean
  #     * `label`: String
  #     * `min_cpu`: Decimal | Supports fractional cores
  #     * `labels`: Array
  #         * `key`: String
  #         * `value`: String
  #     * `min_memory`: Integer
  #     * `name`: String
  #     * `registry_auth`: Boolean
  #     * `registry_custom`: String
  #     * `registry_image_path`: String
  #     * `registry_image_tag`: String
  #     * `remote_block_id`: Integer
  #     * `role`: String | Used in generating variables
  #     * `category`: `String`
  #     * `ssh_block_id`: Integer
  #     * `user_id`: Integer
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `required_containers`: `Array<Integer>`
  #     * `required_by`: `Array<Integer`
  #     * `product`: Object | admin only
  #     * `docker_init`: Boolean | If true, use docker's init system.
  #     * `image_variants`: Array
  #         * `id`: Integer
  #         * `label`: String
  #         * `is_default`: Boolean
  #         * `version`: Integer | Used to sort in drop down list
  #         * `registry_image_tag`: String
  #         * `before_migrate`: String
  #         * `after_migrate`: String
  #         * `rollback_migrate`: String
  #         * `validated_tag`: Boolean
  #         * `validated_tag_updated`: DateTime
  #         * `created_at`: DateTime
  #         * `updated_at`: DateTime
  #     * `container_image_env_params`: Array
  #         * `id`: Integer
  #         * `name`: String
  #         * `label`: String
  #         * `param_type`: `String<static,variable>`
  #         * `env_value`: String
  #         * `static_value`: String
  #         * `updated_at`: DateTime
  #         * `created_at`: DateTime
  #     * `container_image_settings_params`: Array
  #         * `id`: Integer
  #         * `name`: String
  #         * `label`: String
  #         * `param_type`: `String<password,static>` | Password will auto-gen value
  #         * `value`: String
  #         * `updated_at`: DateTime
  #         * `created_at`: DateTime
  #
  def index
    if params[:filter] == 'owned'
      @container_images = current_user.nil? ? [] : paginate(ContainerImage.find_all_for(current_user))
    else
      if current_user
        @container_images = paginate ContainerImage.find_all_for(current_user, true)
      else
        @container_images = paginate ContainerImage.where("active = true AND user_id IS NULL").sorted
      end
    end
    if params[:byname]
      @container_images = @container_images.where(Arel.sql("label ~ '#{params[:byname].to_alpha}'"))
    end
    if params[:filter] == 'isLoadBalancer'
      @container_images = @container_images.where(is_load_balancer: ActiveRecord::Type::Boolean.new.cast(params[:filter][:isLoadBalancer]))
    end
  end

  ##
  # View an image
  #
  # `GET /api/container_images/{id}`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # @see Api::ContainerImagesController#index
  #
  def show
    if current_user
      @container_image = ContainerImage.find_for current_user, { id: params[:id] }
    else
      @container_image = ContainerImage.find_by("id = ? and active = true AND user_id is null", params[:id])
    end
    return api_obj_missing if @container_image.nil?
  end

  ##
  # Update an image
  #
  # `PATCH /api/container_images/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `container_image`: Object
  #     * `label`: String
  #     * `description`: String
  #     * `active`: Boolean | Visible on order form? This does not disable existing containers, nor does it prevent this image from being used in an image collection.
  #     * `role`: String
  #     * `category`: String
  #     * `can_scale`: Boolean
  #     * `min_cpu`: Decimal
  #     * `min_memory`: Integer
  #     * `shm_size`: Integer (Admin) | Override docker's default SHM Size
  #     * `container_image_provider_id`: Integer
  #     * `registry_auth`: Boolean
  #     * `registry_custom`: String
  #     * `registry_image_path`: String
  #     * `registry_username`: String
  #     * `registry_password`: String
  #     * `is_free`: Boolean (Admin)
  #     * `product_id`: Integer (Admin only)
  #     * `override_autoremove`: Boolean (Admin)
  #
  def update
    @container_image = ContainerImage.find_for_edit current_user, id: params[:id]
    return api_obj_missing if @container_image.nil?
    @container_image.current_user = current_user
    if @container_image.update(current_user.is_admin ? admin_update_image_params : update_image_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @container_image.errors.full_messages
    end
  end


  ##
  # Create an image
  #
  # `POST /api/container_images`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `container_image`: Object
  #     * `label`: String
  #     * `description`: String
  #     * `active`: Boolean | Visible on order form? This does not disable existing containers, nor does it prevent this image from being used in an image collection.
  #     * `role`: String
  #     * `category`: String
  #     * `can_scale`: Boolean
  #     * `min_cpu`: Decimal
  #     * `min_memory`: Integer
  #     * `container_image_provider_id`: Integer
  #     * `registry_auth`: Boolean
  #     * `registry_custom`: String
  #     * `registry_image_path`: String
  #     * `registry_image_tag`: String | This will create a new variant
  #     * `registry_username`: String
  #     * `registry_password`: String
  #     * `is_free`: Boolean (Admin)
  #     * `shm_size`: Integer (Admin) | Override docker's default SHM Size
  #     * `product_id`: Integer (Admin only)
  #     * `override_autoremove`: Boolean (Admin)
  #     * `docker_init`: Boolean | If true, use docker's init system.
  #     * `env_params_attributes`: Array
  #         * `name`: String
  #         * `label`: String
  #         * `param_type`: `String<static,variable>`
  #         * `env_value`: String | When `param_type` is `variable`
  #         * `static_value`: String | When `param_type` is `static`
  #     * `ingress_params_attributes`: Array
  #         * `port`: Integer
  #         * `proto`: `String<tcp,udp,tls>`
  #         * `backend_ssl`: Boolean
  #         * `external_access`: Boolean
  #         * `tcp_proxy_opt`: `String<none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn>`
  #     * `setting_params_attributes`: Array
  #         * `name`: String
  #         * `label`: String
  #         * `param_type`: `String<static,variable>`
  #         * `value`: String
  #     * `volume_attributes`: Array
  #         * `label`: String
  #         * `mount_path`: String
  #         * `enable_sftp`: Boolean
  #         * `borg_enabled`: Boolean
  #         * `borg_freq`: String
  #         * `borg_strategy`: `String<file,mysql>`
  #         * `borg_keep_hourly`: Integer
  #         * `borg_keep_daily`: Integer
  #         * `borg_keep_weekly`: Integer
  #         * `borg_keep_monthly`: Integer
  #         * `borg_keep_annually`: Integer
  #         * `borg_pre_backup`: `Array<String>`
  #         * `borg_post_backup`: `Array<String>`
  #         * `borg_pre_restore`: `Array<String>`
  #         * `borg_post_restore`: `Array<String>`
  #         * `borg_rollback`: `Array<String>`
  #
  def create
    @container_image              = ContainerImage.new(current_user.is_admin ? admin_image_params : image_params)
    @container_image.user_id      = current_user.id
    @container_image.current_user = current_user
    if @container_image.save
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :created }
      end
    else
      api_obj_error @container_image.errors.full_messages
    end
  end

  ##
  # Destroy an image
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # `DELETE /api/container_images/{id}`
  #
  def destroy
    @container_image = ContainerImage.find_for_delete current_user, id: params[:id]
    return api_obj_missing if @container_image.nil?
    @container_image.current_user = current_user
    status = :accepted
    msg    = {}
    unless @container_image.destroy
      msg    = { errors: 'Unable to delete container image. Verify there are no containers using this image, and that you have permission to delete it.' }
      status = :internal_server_error
    end
    respond_to do |format|
      format.json { render json: msg, status: status }
      format.xml { render xml: msg, status: status }
    end
  end

  private

  def update_image_params
    params.require(:container_image).permit(
      :active,
      :can_scale,
      :command,
      :container_image_provider_id,
      :description,
      :label,
      :min_cpu,
      :min_memory,
      :registry_auth,
      :registry_custom,
      :registry_image_path,
      :registry_image_tag,
      :role,
      :category,
      :tag_list
    )
  end

  def admin_update_image_params
    params.require(:container_image).permit(
      :active,
      :can_scale,
      :command,
      :container_image_provider_id,
      :description,
      :label,
      :min_cpu,
      :min_memory,
      :registry_auth,
      :registry_custom,
      :registry_image_path,
      :registry_image_tag,
      :role,
      :shm_size,
      :product_id,
      :category,
      :tag_list,
      :is_free,
      :override_autoremove
    )
  end

  def image_params
    params.require(:container_image).permit(
      :active,
      :can_scale,
      :command,
      :container_image_provider_id,
      :description,
      :label,
      :min_cpu,
      :min_memory,
      :registry_auth,
      :registry_custom,
      :registry_image_path,
      :registry_image_tag,
      :role,
      :docker_init,
      :category,
      :tag_list,
      dependency_parents:        [:requires_container_id],
      env_params_attributes:     [:name, :label, :param_type, :env_value, :static_value],
      ingress_params_attributes: [:port, :proto, :backend_ssl, :external_access, :tcp_proxy_opt],
      setting_params_attributes: [:name, :label, :param_type, :value],
      volumes_attributes:        [
        :label,
        :mount_path,
        :enable_sftp,
        :borg_enabled,
        :borg_freq,
        :borg_strategy,
        :borg_keep_hourly,
        :borg_keep_daily,
        :borg_keep_weekly,
        :borg_keep_monthly,
        :borg_keep_annually,
        :borg_pre_backup,
        :borg_post_backup,
        :borg_pre_restore,
        :borg_post_restore,
        :borg_rollback
      ]
    )
  end

  def admin_image_params
    params.require(:container_image).permit(
      :active,
      :can_scale,
      :command,
      :container_image_provider_id,
      :description,
      :label,
      :min_cpu,
      :min_memory,
      :registry_auth,
      :registry_custom,
      :registry_image_path,
      :registry_image_tag,
      :is_free,
      :docker_init,
      :override_autoremove,
      :role,
      :category,
      :product_id,
      :shm_size,
      :tag_list,
      dependency_parents:        [:requires_container_id],
      env_params_attributes:     [:name, :label, :param_type, :env_value, :static_value],
      ingress_params_attributes: [:port, :proto, :backend_ssl, :external_access, :tcp_proxy_opt],
      setting_params_attributes: [:name, :label, :param_type, :value],
      volumes_attributes:        [
                       :label,
                       :mount_path,
                       :enable_sftp,
                       :borg_enabled,
                       :borg_freq,
                       :borg_strategy,
                       :borg_keep_hourly,
                       :borg_keep_daily,
                       :borg_keep_weekly,
                       :borg_keep_monthly,
                       :borg_keep_annually,
                       :borg_pre_backup,
                       :borg_post_backup,
                       :borg_pre_restore,
                       :borg_post_restore,
                       :borg_rollback
                     ]
    )
  end

end
