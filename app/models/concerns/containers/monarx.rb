module Containers
  module Monarx
    extend ActiveSupport::Concern

    included do

      after_destroy :clean_monarx_cache

    end

    private

    # It's possible we're deleting a scaled service and the active agent ID
    # is now moved to another container.
    def clean_monarx_cache
      Rails.cache.delete "monarx_url_#{service.name}"
      Rails.cache.delete "monarx_agentid_#{service.name}"
    end

  end
end
