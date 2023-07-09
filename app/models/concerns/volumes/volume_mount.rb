module Volumes
  module VolumeMount
    extend ActiveSupport::Concern

    included do
      before_validation :modify_mount_point
    end

    class_methods do
      def safe_mount(path)
        p = []
        path.split('/').each do |i|
          next if i.blank?
          if i.start_with?('.')
            # Allow dot files/directories (Zaru will not allow it)
            i = i[1..-1]
            p << ".#{Zaru.sanitize!(i).gsub(" ","_")}"
          else
            p << Zaru.sanitize!(i).gsub(" ","_")
          end
        end
        "/#{p.join('/')}"
      end
    end

    def modify_mount_point
      self.mount_path = self.class.safe_mount(self.mount_path)
    end

  end
end
