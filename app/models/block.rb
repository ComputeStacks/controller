##
# Block
#
# Parent object for block contents
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute title
#   @return [String]
#
# @!attribute [r] content_key
#   @return [String]
#
class Block < ApplicationRecord

  has_many :block_contents, dependent: :destroy, inverse_of: :block

  before_destroy :safe_to_delete?, prepend: true

  accepts_nested_attributes_for :block_contents

  validates :title, presence: true
  validates :content_key, uniqueness: true, allow_nil: true

  def find_content_by_locale(locale)
    c = block_contents.find_by(locale: locale)
    c = block_contents.find_by(locale: ENV['LOCALE']) if c.nil?
    c = block_contents.find_by(locale: 'en') if c.nil? && ENV['LOCALE'] != 'en'
    c
  end

  private

  def safe_to_delete?
    throw(:abort) unless content_key.blank?
  end

end
