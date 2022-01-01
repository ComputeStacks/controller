module Projects
  module ProjectHealth
    extend ActiveSupport::Concern

    # error
    # degraded
    # deleting
    # deployed
    # pending
    # unknown
    # working
    # def health
    #   return 'deleting' if status == 'deleting'
    #   return 'pending' if services.empty?
    #   return 'error' if services.where(status: 'error').exists?
    #   if services.where("status = ? OR status = ?", 'pending', 'working').exists?
    #     return 'working'
    #   end
    #   unless services.where.not(status: 'deployed').exists?
    #     return 'deployed'
    #   end
    #   'unknown'
    # end

  end
end
