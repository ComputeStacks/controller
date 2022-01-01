module Users
  # Maintain legacy auth and communication (e.g. OnApp).
  #
  # ALL are deprecated and need to be removed or replaced with OAuth.
  module LegacyRemote
    extend ActiveSupport::Concern

    included do
      has_many :auths, class_name: 'ProvisionDriver::UserAuth', dependent: :destroy
    end

  end
end
