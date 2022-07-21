##
# Container Service Host Entry
class Api::ContainerServices::HostEntriesController < Api::ContainerServices::BaseController

  before_action :find_entry, only: [:show, :update, :destroy]

  ##
  # List all host entries
  #
  # `GET /api/container_services/{container-service-id}/host_entries`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `host_entries`: Array
  #     * `hostname`: String
  #     * `ipaddr`: String
  #     * `keep_updated`: Boolean | If true, will look for `source_image` in project.
  #     * `source_image`: Object
  #         * `id`: Integer
  #         * `label`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @entries = @service.host_entries
  end

  ##
  # View Host Entry
  #
  # `GET /api/container_services/{container-service-id}/host_entries/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `host_entries`: Object
  #     * `hostname`: String
  #     * `ipaddr`: String
  #     * `keep_updated`: Boolean | If true, will look for `source_image` in project.
  #     * `source_image`: Object
  #         * `id`: Integer
  #         * `label`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show; end

  ##
  # Update Host Entry
  #
  # `PATCH /api/container_services/{container-service-id}/host_entries/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `host_entries`: Object
  #     * `hostname`: String
  #     * `ipaddr`: String
  #     * `keep_updated`: Boolean | If true, will look for `source_image` in project.
  #
  def update
    if @entry.update(update_entry_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @entry.errors.full_messages
    end
  end

  ##
  # Create Host Entry
  #
  # `POST /api/container_services/{container-service-id}/host_entries`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `host_entries`: Object
  #     * `hostname`: String
  #     * `ipaddr`: String
  #
  def create
    @entry = @service.host_entries.new(entry_params)
    @entry.current_user = current_user
    if @entry.save
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :created }
      end
    else
      api_obj_error @entry.errors.full_messages
    end
  end

  ##
  # Delete Host Entry
  #
  # `DELETE /api/container_services/{container-service-id}/host_entries/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  def destroy
    @entry.destroy ? api_obj_destroyed : api_obj_error(@entry.errors.full_messages)
  end

  private

  def find_entry
    @entry = @service.host_entries.find_by id: params[:id]
    return api_obj_missing if @entry.nil?
    @entry.current_user = current_user
  end

  def entry_params
    params.require(:host_entry).permit(:hostname, :ipaddr)
  end

  def update_entry_params
    params.require(:host_entry).permit(:hostname, :ipaddr, :keep_updated)
  end
end
