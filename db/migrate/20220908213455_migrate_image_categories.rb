class MigrateImageCategories < ActiveRecord::Migration[7.0]
  def change
    ContainerImage.all.each do |i|
      cat = case i.role_class
            when 'web'
              'apps'
            when 'database'
              'databases'
            when 'cache'
              'key/value & caching'
            when 'dev'
              'development tools'
            else
              'other'
            end

      i.update_column :category, cat

    end
  end
end
