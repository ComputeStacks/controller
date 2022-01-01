##
# =Additional Validations for User
class UserValidator < ActiveModel::Validator

  def validate(user)
    unless currency_allowed?(user.currency)
      user.errors.add(:currency, "Unknown currency.")
    end
  end

  private

  def currency_allowed?(currency)
    return true if currency.nil?
    table = Money::Currency.table
    avail = table.map { |i,k| k[:iso_code] }
    avail.include?(currency)
  end

end