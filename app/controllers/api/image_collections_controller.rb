##
# Container Image Collections
class Api::ImageCollectionsController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :images_read }, unless: :current_user

  ##
  # List all images
  #
  # `GET /api/container_images`
  #
  # **OAuth Authorization Required**: `images_read`
  #
  # * `image_collections`: Array
  #     * `id`: Integer
  #     * `label`: String
  #     * `active`: Boolean
  #     * `sort`: Integer
  #     * `container_images`: Array<ContainerImage>
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  def index
    @collections = paginate ContainerImageCollection.where active: true
  end

end
