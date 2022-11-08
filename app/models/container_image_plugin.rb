##
# Image Plugins
#
# @!attribute name [ro]
#   @return [String]
#
# @!attribute active
#   @return [Boolean]
#
class ContainerImagePlugin < ApplicationRecord

  include Auditable
  include ImagePlugins::MonarxPlugin

  default_scope { order name: :desc }
  scope :active, -> { where active: true }

  has_and_belongs_to_many :container_images

  validates :name, uniqueness: true

  before_update :block_name_changes

  # @return [Boolean]
  def available?
    return false unless active
    case name
    when 'monarx'
      monarx_available?
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
    else
      false
    end
  end

  private

  # We find plugins by name, so don't allow it to be changed!
  def block_name_changes
    errors.add(:name, 'unable to change name') if name_changed?
  end

end
