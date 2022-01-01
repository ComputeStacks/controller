# ProductModule
#
# @deprecated Will soon completely remove the ProvisionDriver & ProductModule.
#             This is a relic of our previous Virtual Machine integration.
#             Currently, this is only used by our DNS integration.
#
class ProductModule < ApplicationRecord

  has_and_belongs_to_many :provision_drivers

  belongs_to :primary, class_name: 'ProvisionDriver', foreign_key: 'primary_id'

  def default_driver
    primary.nil? ? provision_drivers.first : primary
  end

end
