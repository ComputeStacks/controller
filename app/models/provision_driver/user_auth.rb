# @deprecated Provision Driver is going away.
class ProvisionDriver::UserAuth < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :provision_driver, optional: true

  serialize :details, coder: JSON

  after_create :refresh_limits!

  def client
    eval("#{provision_driver.module_name}::Client").new(provision_driver.endpoint, cloud_auth)
  end

  def cloud_user
    eval("#{provision_driver.module_name}::User").new(client, details["id"])
  end

  def refresh_limits!
    data = details
    begin
      result = cloud_user.limits
    rescue
      return false
    end
    result.each_key do |k|
      param = result[k]
      case k
      when "disk"
        # Format into multiple of 5.
        param = param.to_i
        param = if param < 10
          100 # Something weird is going on.
        else
          (param / 5).round * 5
        end
      when "memory"
        # Convert to GB.
        param = param.to_i / 1024
        param = if param > 1
          # Don't allow more than 32GB.
          (param > 32) ? 32 : param
        else
          # Something weird..
          12
        end
      when "cpu"
        param = param.to_i
        param = if param > 1
          # Don't allow more than 12 cores.
          (param > 12) ? 12 : param
        else
          # Something weird...
          2
        end
      end
      data[k] = param
    end
    update_attribute :details, data
  end

  private

  def cloud_auth
    eval("#{provision_driver.module_name}::Auth").new(details["id"], username, api_key.nil? ? nil : Secret.decrypt!(api_key), api_secret.nil? ? nil : Secret.decrypt!(api_secret))
  end
end
