##
# ContainerService Environmental Parameter
#
# Used to populate Environmental variables within a container
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute name
#   @return [String]
#
# @!attribute param_type
#   @return [static,variable]
#
# @!attribute env_value
#   @return [String] value when param_type is variable
#
# @!attribute static_value
#   @return [String] value when param_type is static
#
# @!attribute container_service
#   @return [Deployment::ContainerService]
#
# @!attribute deployment
#   @return [Deployment]
#
# @!attribute parent_param
#   @return [ContainerImage::EnvParam]
#
class ContainerService::EnvConfig < ApplicationRecord

  include Auditable

  scope :sorted, -> { order( Arel.sql('lower(name)') ) }

  belongs_to :container_service, class_name: "Deployment::ContainerService"
  belongs_to :parent_param, class_name: "ContainerImage::EnvParam", foreign_key: "container_image_env_param_id", optional: true

  has_one :deployment, through: :container_service

  attr_accessor :env_value,
                :static_value,
                :skip_metadata_refresh

  before_validation :set_value

  after_save :refresh_metadata, unless: Proc.new { |i| i.skip_metadata_refresh }

  validates :param_type, inclusion: { in: %w(static variable) }
  validates :name, presence: true

  private

  def set_value
    self.label = self.name if self.label.blank?
    unless static_value.blank? && env_value.blank?
      case param_type
      when 'static'
        self.value = static_value
      when 'variable'
        self.value = env_value
      end
    end
  end

  def refresh_metadata
    return if deployment.nil?
    ProjectWorkers::RefreshMetadataWorker.perform_async deployment.id
  end

end
