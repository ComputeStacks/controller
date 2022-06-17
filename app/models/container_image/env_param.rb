##
# ContainerImage EnvParam
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute env_value
#   @return [String] Value when `param_type` is `variable`.
#
# @!attribute name
#   @return [String]
#
# @!attribute label
#   @return [String]
#
# @!attribute param_type
#   @return [static,variable]
#
# @!attribute static_value
#   @return [String] Value when `param_type` is `static`.
#
# @!attribute container_image
#   @return [ContainerImage]
#
# @!attribute created_at
#   @return [DateTime]
#
# @!attribute updated_at
#   @return [DateTime]
#
class ContainerImage::EnvParam < ApplicationRecord

  include Auditable

  scope :sorted, -> { order( Arel.sql('lower(name)') ) }

  belongs_to :container_image
  has_many :dependent_params, class_name: "ContainerService::EnvConfig", foreign_key: "container_image_env_param_id", dependent: :nullify

  attr_accessor :env_value, :static_value

  before_validation :set_value

  validates :param_type, inclusion: { in: %w(static variable) }
  validates :name, presence: true
  validate :valid_env_param, if: -> { param_type == 'variable' }

  def csrn
    "csrn:caas:template:vol:#{resource_name}:#{id}"
  end

  def resource_name
    return "null" if label.blank?
    label.strip.downcase.gsub(/[^a-z0-9\s]/i,'').gsub(" ","_")[0..10]
  end

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

  def valid_env_param
    unless container_image&.available_vars.include?(env_value)
      errors.add(:env_value, 'not a valid variable')
    end
  end

end
