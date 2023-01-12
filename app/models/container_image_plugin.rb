##
# Image Plugins
#
# @!attribute name [ro]
#   @return [String]
#
# @!attribute active
#   @return [Boolean]
#
# @!attribute is_optional
#   Can the user selectively turn this on or off?
#   @return [Boolean]
#
class ContainerImagePlugin < ApplicationRecord

  include Auditable
  include ImagePlugins::MonarxPlugin

  default_scope { order name: :desc }
  scope :active, -> { where active: true }
  scope :optional, -> { where is_optional: true }

  has_and_belongs_to_many :container_images
  has_many :service_plugins, class_name: "Deployment::ContainerService::ServicePlugin", dependent: :destroy
  belongs_to :product, optional: true

  validates :name, uniqueness: true, inclusion: { in: %w(monarx demo another_demo required_demo) }

  def label
    name.titleize
  end

  # @return [Boolean]
  def available?
    return false unless active
    case name
    when 'monarx'
      monarx_available?
    when 'demo', 'another_demo', 'required_demo'
      true
    else
      false
    end
  end

  # Determine who can enable/disable a plugin on an image
  # Does not effect using the plugin on an image that has it enabled.
  #
  # @return [Boolean]
  def can_enable?(user)
    return false unless active
    case name
    when 'monarx'
      monarx_can_enable?(user)
    when 'demo', 'another_demo', 'required_demo'
      user.is_admin
    else
      false
    end
  end

end
