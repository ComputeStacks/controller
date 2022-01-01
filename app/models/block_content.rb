##
# =Content Block
#
# body:text
# locale:string
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute block
#   @return [Block]
#
# @!attribute locale
#   @return [String]
#
# @!attribute body
#   @return [String]
#
class BlockContent < ApplicationRecord

  belongs_to :block, inverse_of: :block_contents
  validates_presence_of :block

  def parsed_body(obj)
    data = Liquid::Template.parse(body)
    data.render(body_vars_by_obj(obj))
  rescue
    body
  end

  def body_vars_by_obj(obj)
    obj.respond_to?(:content_variables) ? obj.content_variables : {}
  end

end
