module Regions
  module NfsStorage
    extend ActiveSupport::Concern

    included do
      validate :valid_nfs_path?
      validate :valid_nfs_host?
      validate :valid_nfs_controller?

      before_save :sanitize_nfs_path
    end

    private

    def valid_nfs_host?
      return unless volume_backend == 'nfs'
      unless nfs_remote_host.count('.') == 3
        errors.add(:nfs_remote_host, 'not a valid IP address')
      end
    end

    def valid_nfs_controller?
      return if nfs_controller_ip.blank?
      unless nfs_controller_ip.count('.') == 3
        errors.add(:nfs_controller_ip, 'not a valid IP address')
      end
    end

    ##
    # Prior to saving, ensure we have a clean path
    def sanitize_nfs_path
      self.nfs_remote_path = nfs_remote_path.strip # remove trailing whitespace
      self.nfs_remote_path = nfs_remote_path[-1] == '/' ? nfs_remote_path.delete_suffix('/') : nfs_remote_path
    end

    ##
    # Validate we have something that looks like a path
    def valid_nfs_path?
      if nfs_remote_path.blank?
        errors.add(:nfs_remote_path, 'is missing')
      elsif nfs_remote_path.count('/').zero?
        errors.add(:nfs_remote_path, 'is not a valid path')
      end
    end

  end
end
