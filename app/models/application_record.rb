class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  def global_id
    to_global_id.to_s
  end

end
