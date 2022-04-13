class UpdateSettings < ActiveRecord::Migration[6.1]
  def change
    Feature.setup!
    Setting.setup!

    if Setting.belco_enabled?
      Feature.find_by(name: 'setting_belco').update active: true
    end

  end
end
