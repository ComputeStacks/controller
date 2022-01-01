##
# Container Image Providers Controller
#
# Providers for Container Images.
#
class Api::ContainerImageProvidersController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :images_read }, unless: :current_user

  before_action :find_provider, only: :show

  ##
  # List all available image providers.
  #
  # **OAuth Authorization Required**: `images_read`
  #
  # `GET /container_image_providers`
  #
  # * `container_image_providers`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `hostname`: String
  #     * `is_default`: Boolean
  #     * `updated_at`: DateTime
  #     * `created_at`: DateTime
  #
  # @example
  #    {
  #      "container_image_providers": [
  #        {
  #          "id": 2,
  #          "name": "Quay",
  #          "hostname": "quay.io",
  #          "is_default": false,
  #          "updated_at": "2019-05-18T00:20:55.400Z",
  #          "created_at": "2019-05-18T00:11:46.946Z"
  #        },
  #        {
  #          "id": 4,
  #          "name": "Github",
  #          "hostname": "docker.pkg.github.com",
  #          "is_default": false,
  #          "updated_at": "2019-05-19T04:03:37.647Z",
  #          "created_at": "2019-05-18T00:11:46.950Z"
  #        },
  #        {
  #          "id": 3,
  #          "name": "Google",
  #          "hostname": "gcr.io",
  #          "is_default": false,
  #          "updated_at": "2019-05-19T04:08:45.354Z",
  #          "created_at": "2019-05-18T00:11:46.948Z"
  #        },
  #        {
  #          "id": 1,
  #          "name": "DockerHub",
  #          "hostname": "",
  #          "is_default": true,
  #          "updated_at": "2019-05-19T04:20:57.882Z",
  #          "created_at": "2019-05-18T00:11:46.942Z"
  #        }
  #      ]
  #    }
  #
  #
  def index
    @providers = ContainerImageProvider.where("container_registry_id is null")
  end

  ##
  # Show a single Container Image Provider
  #
  # **OAuth Authorization Required**: `images_read`
  #
  # `GET /container_image_providers/{id}`
  #
  # * `container_image_providers`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `hostname`: String
  #     * `is_default`: Boolean
  #     * `updated_at`: DateTime
  #     * `created_at`: DateTime
  #
  def show; end

  private

  def find_provider
    @provider = ContainerImageProvider.where("id = ? AND container_registry_id is null", params[:id])
    api_obj_missing if @provider.nil?
  end

end
