# @deprecated Provision Driver is going away.
class ProvisionDriver::UserAuth < ApplicationRecord

  belongs_to :user, optional: true
  belongs_to :provision_driver, optional: true

  serialize :details, JSON

  after_create :refresh_limits!

  def client
    eval("#{self.provision_driver.module_name}::Client").new(self.provision_driver.endpoint, cloud_auth)
  end

  def cloud_user
    eval("#{self.provision_driver.module_name}::User").new(client, self.details['id'])
  end

  def refresh_limits!
    data = self.details
    begin
      result = cloud_user.limits
    rescue => e
      return false
    end
    result.each_key do |k|
      param = result[k]
      case k
      when "disk"
        # Format into multiple of 5.
        param = param.to_i
        if param < 10
          param = 100 # Something weird is going on.
        else
          param = (param / 5).round * 5
        end
      when 'memory'
        # Convert to GB.
        param = param.to_i / 1024
        if param > 1
          # Don't allow more than 32GB.
          param = param > 32 ? 32 : param
        else
          # Something weird..
          param = 12
        end
      when 'cpu'
        param = param.to_i
        if param > 1
          # Don't allow more than 12 cores.
          param = param > 12 ? 12 : param
        else
          # Something weird...
          param = 2
        end
      end
      data[k] = param
    end
    self.update_attribute :details, data
  end

  private

  def cloud_auth
    eval("#{self.provision_driver.module_name}::Auth").new(self.details['id'], self.username, self.api_key.nil? ? nil : Secret.decrypt!(self.api_key), self.api_secret.nil? ? nil : Secret.decrypt!(self.api_secret))
  end

end
