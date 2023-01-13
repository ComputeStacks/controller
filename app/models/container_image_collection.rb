# ContainerImageCollection
#
# @!attribute label
#   @return [String]
# @!attribute active
#   @return [Boolean]
# @!attribute sort
#   @return [Integer]
#
class ContainerImageCollection < ApplicationRecord

  include Auditable

  default_scope { order :sort }
  scope :available, -> { where active: true }

  has_and_belongs_to_many :container_images

  attr_accessor :add_image_id

  after_commit :add_image_by_id

  def image_icons
    container_images.where(is_load_balancer: false).order(:name).uniq
  end

  def all_images_valid?
    has_default_variant? && dependencies_met?
  end

  # @return [Boolean]
  def has_default_variant?
    container_images.each do |i|
      return false if i.default_variant.nil?
    end
    true
  end

  # Require all dependent images
  # @return [Boolean]
  def dependencies_met?
    container_images.each do |i|
      i.dependencies.each do |ii|
        unless container_images.exists?(ii.id)
          return false
        end
      end
    end
    true
  end

  def self.with_valid_collections(query)
    query.each do |q|
      unless q.all_images_valid?
        query = query.excluding q
      end
    end
    query
  end

  private

  def add_image_by_id
    unless add_image_id.blank?

      image = ContainerImage.find_by id: add_image_id
      if image && !container_images.exists?(image.id)
        container_images << image
      end

    end
  end

end
