##
# Container Image Image Variant
# Used to manage variants of an image and allow moving between versions
#
# @!attribute label
#   @return [String]
# @!attribute is_default
#   @return [Boolean]
# @!attribute version
#   @return [Integer] Used for sorting
# @!attribute registry_image_tag
#   @return [String]
# @!attribute container_image
#   @return [ContainerImage]
# @!attribute before_migrate
#   Run before migrating to this variant
#   @return [String]
# @!attribute after_migrate
#   Run after migrating to this variant
#   @return [String]
# @!attribute rollback_migrate
#   If before or after migrate fail, we run this.
#   @return [String]
# @!attribute validated_tag
#   @return [Boolean]
# @!attribute validated_tag_updated
#   @return [DateTime]
#
class ContainerImage::ImageVariant < ApplicationRecord

  include Auditable
  include ContainerImages::ImageRegistryValidator

  default_scope { order :version }
  scope :default, -> { where is_default: true }

  # Ownership
  belongs_to :container_image
  has_one :user, through: :container_image

  # Provider
  has_one :container_image_provider, through: :container_image
  has_one :container_registry, through: :container_image_provider

  # Dependencies
  has_many :container_services, class_name: 'Deployment::ContainerService', dependent: :restrict_with_error
  has_many :containers, through: :container_services

  has_many :image_dependents, class_name: "ContainerImage::ImageRel", foreign_key: "default_variant_id", dependent: :nullify

  # Validations
  validates :registry_image_tag, presence: true

  before_save :set_default_label
  before_create :setup_defaults
  before_update :change_default

  # Destruction
  attr_accessor :skip_default_delete
  before_destroy :halt_if_default, prepend: true

  def csrn
    "csrn:caas:template:image_variant:#{resource_name}:#{id}"
  end

  def resource_name
    parent_rn = container_image.resource_name
    return "null" if parent_rn == "null" && label.blank?
    return parent_rn if label.blank?
    "#{parent_rn}/#{name.strip.downcase.gsub(/[^a-z0-9\s]/i,'').gsub(" ","_")[0..10]}"
  end

  def friendly_name
    "#{container_image.label}-#{label.blank? ? registry_image_tag : label}"
  end

  def full_image_path
    "#{container_image.provider_path}#{container_image.provider_path.blank? ? '' : '/'}#{container_image.registry_image_path}:#{registry_image_tag}"
  end

  def exists_on_node?(node)
    Docker::Image.exist?(full_image_path, {}, node.client)
  rescue Excon::Error::Socket, Errno::ECONNREFUSED, IO::EINPROGRESSWaitWritable => connection_error
    SystemEvent.create!(
      message: "Error Connecting to Node",
      log_level: "warn",
      data: {
        error: connection_error.message
      },
      event_code: '734d76176fcecb49'
    )
    nil
  rescue => e
    ExceptionAlertService.new(e, '7dcc930ebebcae8c').perform
    SystemEvent.create!(
      message: "Error retrieving image from node",
      log_level: "warn",
      data: {
        error: e.message
      },
      event_code: '7dcc930ebebcae8c'
    )
    nil
  end

  ##
  # Helper to decide if we should pull this image
  #
  # @param [Node] node
  def pull_image?(node)
    !exists_on_node?(node) || !user.nil?
  end

  private

  def change_default
    return unless is_default_changed?
    if is_default_was # was true
      errors.add(:base, "Unable to remove the default tag. Please choose a new default instead.")
      throw :abort
    elsif is_default_changed? && is_default # false to true
      existing_default = container_image.image_variants.default.first
      existing_default&.update_column :is_default, false
    end
  end

  def setup_defaults
    unless container_image.has_default_variant?
      self.is_default = true
    end
    self.version = if container_image.image_variants.last
                    container_image.image_variants.last.version + 1
                  else
                    0
                  end
  end

  def halt_if_default
    return if skip_default_delete
    if is_default
      errors.add(:base, "unable to delete default variant")
      throw :abort
    end
  end

  def set_default_label
    self.label = registry_image_tag if label.blank?
  end

end
