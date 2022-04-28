class LeDnsSleep < ActiveRecord::Migration[6.1]
  def change
    Setting.le_dns_sleep
  end
end
