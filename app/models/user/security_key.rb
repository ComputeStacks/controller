##
# Security Key
#
# Webauthn security keys
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute public_key
#   @return [String]
#
# @!attribute counter
#   @return [Integer]
#
# @!attribute label
#   @return [String]
#
# @!attribute webauthn_id
#   @return [String]
#
class User::SecurityKey < ApplicationRecord

  belongs_to :user

  validates :public_key, :webauthn_id, :label, presence: true
  validates :webauthn_id, uniqueness: true
  validates :counter, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 2**32 - 1 }

end
