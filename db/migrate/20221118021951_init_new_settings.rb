class InitNewSettings < ActiveRecord::Migration[7.0]
  def change
    Setting.setup!
  end
end
