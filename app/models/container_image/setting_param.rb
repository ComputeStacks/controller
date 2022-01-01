##
# Container Image Setting Param
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute name
#   @return [String]
#
# @!attribute label
#   @return [String]
#
# @!attribute param_type
#   @return [static,password] password will autogen
#
# @!attribute value
#   @return [String] Ignored if `param_type` is `password`.
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
class ContainerImage::SettingParam < ApplicationRecord

  include Auditable

  scope :sorted, -> { order( Arel.sql('lower(name)') ) }

  belongs_to :container_image
  has_many :dependent_params, class_name: "ContainerService::SettingConfig", foreign_key: "container_image_setting_param_id", dependent: :nullify

  validates :param_type, inclusion: { in: %w(password static) }
  validates :name, presence: true

  before_validation :set_label

  private

  def set_label
    self.label = self.name if self.label.blank?
  end

end
