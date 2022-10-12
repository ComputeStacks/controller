##
# ContainerImage
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute active
#   Visible on order form? This does not disable existing containers, nor does it prevent this image from being used in an image collection.
#   @return [Boolean]
#
# @!attribute is_load_balancer
#   @return [Boolean]
#
# @!attribute can_scale
#   @return [Boolean]
#
# @!attribute is_free
#   @return [Boolean]
#
# @!attribute registry_auth
#   @return [Boolean]
#
# @!attribute validated_tag
#   @return [Boolean]
#
# @!attribute force_local_volume
#   @return [Boolean]
#
# @!attribute command
#   @return [String]
#
# @!attribute description
#   @return [String]
#
# @!attribute icon_url
#   @return [String]
#
# @!attribute label
#   @return [String]
#
# @!attribute [r] name
#   @return [String]
#
# @!attribute registry_custom
#   @return [String]
#
# @!attribute registry_image_path
#   @return [String]
#
# @!attribute registry_image_tag
#   @return [String]
#
# @!attribute role
#   @return [String] Used for generating variable names
#
# @!attribute category
#   @return [String] Used to organize images on order screen.
#
# @!attribute container_image_provider
#   @return [ContainerImageProvider]
#
# @!attribute domains_block
#   @return [Block]
#
# @!attribute general_block
#   @return [Block]
#
# @!attribute min_memory
#   @return [Integer] Minimum memory for this image, in MB.
#
# @!attribute min_cpu
#   @return [Decimal] Minimum CPU Cores
#
# @!attribute remote_block
#   @return [Block]
#
# @!attribute ssh_block
#   @return [Block]
#
# @!attribute user
#   @return [User] owner. if nil, publicly available image.
#
# @!attribute required_containers
#   @return [Array<ContainerImage>] Images required by this image.
#
# @!attribute env_params
#   @return [Array<ContainerImage::EnvParam>]
#
# @!attribute ingress_params
#   @return [Array<ContainerImage::IngressParam>]
#
# @!attribute setting_params
#   @return [Array<ContainerImage::SettingParam>]
#
# @!attribute volumes
#   @return [Array<ContainerImage::VolumeParam>]
#
# @!attribute validated_tag_updated
#   @return [DateTime]
#
# @!attribute deployed_services
#   @return [Array<Deployment::ContainerService>]
#
# @!attribute deployed_containers
#   @return [Array<Deployment::Container>]
#
# @!attribute container_image_collaborators
#   @return [Array<ContainerImageCollaborator>]
#
# @!attribute collaborators
#   @return [Array<User>]
#
class ContainerImage < ApplicationRecord
  acts_as_taggable

  include Auditable
  include Authorization::ContainerImage
  include ContainerImages::ImageAvatar
  include ContainerImages::ImageParamManager
  include ImageCloner
  include ProviderForContainerImage
  include UrlPathFinder

  scope :is_public, -> { where(user: nil) }
  scope :non_lbs, -> { where( Arel.sql("container_images.is_load_balancer = false") ) }
  scope :available, -> { where active: true }
  scope :sorted, -> { order( Arel.sql('lower(container_images.label)') ) }

  has_many :image_variants, class_name: 'ContainerImage::ImageVariant', dependent: :destroy

  has_many :deployed_services, through: :image_variants, source: :container_services, dependent: :restrict_with_error
  has_many :deployed_containers, through: :image_variants, source: :containers

  has_many :dependency_parents, class_name: "ContainerImage::ImageRel", foreign_key: "container_image_id", dependent: :destroy
  has_many :dependencies, through: :dependency_parents, source: :dependency

  has_many :required_by_parent, class_name: "ContainerImage::ImageRel", foreign_key: "requires_container_id", dependent: :destroy
  has_many :parent_containers, through: :required_by_parent, source: :container_image

  belongs_to :user, optional: true

  has_many :env_params, class_name: 'ContainerImage::EnvParam', dependent: :destroy
  has_many :ingress_params, class_name: 'ContainerImage::IngressParam', dependent: :destroy
  has_many :setting_params, class_name: 'ContainerImage::SettingParam', dependent: :destroy
  has_many :host_entries, class_name: 'ContainerImage::CustomHostEntry', dependent: :destroy

  has_many :host_entry_dependents,
           class_name: 'ContainerImage::CustomHostEntry',
           inverse_of: :source_image,
           dependent: :destroy

  has_many :volumes, class_name: "ContainerImage::VolumeParam", dependent: :destroy

  has_many :container_image_collaborators
  has_many :collaborators, through: :container_image_collaborators, source: :collaborator

  has_and_belongs_to_many :container_image_collections

  # Content Sections
  belongs_to :general_block, class_name: 'Block', optional: true
  belongs_to :remote_block, class_name: 'Block', optional: true
  belongs_to :ssh_block, class_name: 'Block', optional: true
  belongs_to :domains_block, class_name: 'Block', optional: true

  before_validation :set_name

  validate :ensure_tag, on: :create
  validates :category, presence: true
  validates :name, uniqueness: true
  validates :name, presence: true
  validates :label, presence: true
  validates :registry_image_path, presence: true
  validates :role, presence: true
  validates :min_cpu, numericality: { greater_than_or_equal_to: 0.0 }
  validates :min_memory, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  accepts_nested_attributes_for :env_params
  accepts_nested_attributes_for :dependency_parents
  accepts_nested_attributes_for :ingress_params
  accepts_nested_attributes_for :setting_params
  accepts_nested_attributes_for :volumes

  before_destroy :clean_variants, prepend: true
  before_destroy :clean_collaborators

  before_save :update_variant_sorting
  before_save :format_category

  # Setup initial variant after creation
  after_create_commit :setup_default_tag
  attr_accessor :registry_image_tag, :skip_variant_setup, :variant_pos

  def csrn
    "csrn:caas:template:image:#{resource_name}:#{id}"
  end

  def resource_name
    return "null" if name.blank?
    name.strip.downcase.gsub(/[^a-z0-9\s]/i,'').gsub(" ","_")[0..10]
  end

  def default_variant
    image_variants.find_by is_default: true
  end

  def has_default_variant?
    image_variants.where(is_default: true).exists?
  end

  # Returns valid pull status
  # possible values are: `:valid`, `:invalid`, `:pending`, and `:partial`
  def variant_pull_status
    if image_variants.where(validated_tag: false).exists?
      return :pending if has_pending_pull_validations?
      image_variants.where(validated_tag: true).exists? ? :partial : :invalid
    else
      :valid
    end
  end

  def has_pending_pull_validations?
    image_variants.where(validated_tag_updated: nil).exists?
  end

  def uses_load_balancer?
    ingress_params.where(external_access: true).exists?
  end

  def has_custom_blocks?
    !(general_block.nil? && remote_block.nil? && ssh_block.nil? && domains_block.nil?)
  end

  def service_container?
    %w(cmptstks/phpmyadmin).include?(registry_image_path)
  end

  def content_variables
    {
      "user" => user&.full_name,
      "image" => label
    }
  end

  def self.by_category(query)
    result = {}
    query.each do |i|
      (result[i.category] ||= []) << i
    end
    result.sort
  end

  private

  def set_name
    return nil if self.label.blank?
    return true unless self.name.blank?
    name_check = if self.user
                   "#{self.label.strip.parameterize}-#{self.user.id}"
                 else
                   self.label.strip.parameterize
                 end
    self.name = ContainerImage.where(name: name_check).exists? ? "#{name_check}#{SecureRandom.rand(1..1000)}" : name_check
  end

  def allowed_params
    %w(env args settings)
  end

  def clean_collaborators
    return if container_image_collaborators.empty?
    if user_performer.nil?
      errors.add(:base, "Missing user performing delete action.")
      return
    end
    container_image_collaborators.each do |i|
      i.current_user = user_performer
      unless i.destroy
        errors.add(:base, %Q(Error deleting collaborator #{i.id} - #{i.errors.full_messages.join("\n")}))
      end
    end
  end

  # Ensure we have a tag
  def ensure_tag
    if !skip_variant_setup && registry_image_tag.blank?
      errors.add(:base, "Missing image tag")
    end
  end

  # Create initial default tag on commit
  def setup_default_tag
    image_variants.create!(
      registry_image_tag: registry_image_tag,
      label: registry_image_tag,
      version: 0,
      is_default: true
    ) unless skip_variant_setup
  end

  # Ensure clean destruction of variants before deleting image
  def clean_variants
    image_variants.each do |i|
      i.skip_default_delete = true
      unless i.destroy
        errors.add(:base, "error with variant #{i.label}: #{i.errors.full_messages.join(" ")}")
        throw :abort
      end
    end
  end

  def update_variant_sorting
    return unless variant_pos.is_a?(Array)
    k = 0
    variant_pos.each do |i|
      v = image_variants.find_by id: i
      if v.nil?
        errors.add(:base, "Unknown variant #{i}")
        next
      end
      unless v.update version: k
        errors.add(:base, "Error saving variant #{v.id}: #{v.errors.full_messages.join(' ')}")
      end
      k += 1
    end
  end

  def format_category
    return if category.blank?
    self.category = category.strip.downcase
  end

  def icon_exists?(icon_path)
    if Rails.env.production?
      all_assets = Rails.application.assets_manifest.find_sources(icon_path)

      if all_assets
        Rails.application.assets_manifest.assets.keys.include?(icon_path)
      else
        false
      end
    else
      Rails.application.assets.find_asset(icon_path) != nil
    end
  end

end
