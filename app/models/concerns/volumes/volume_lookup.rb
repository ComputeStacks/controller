module Volumes
  module VolumeLookup
    extend ActiveSupport::Concern

    class_methods do

      # Determine ID given a volume path.
      def name_by_path(remote_path)
        if remote_path.split("/var/lib/docker/volumes/").count > 1
          return remote_path.split("/var/lib/docker/volumes/").last.gsub("/_data", "").strip
        end
        nil
      end

      ##
      # Identify attached services and details for a given volume name
      #
      # This is used by our import process to identify who a volume belongs to,
      # and where it's mounted inside the container.
      def inspect_volume_by_name(volume_name)
        result = []
        Node.online.each do |node|
          node.list_all_containers.each do |c|
            c.info['Mounts'].each do |mount|
              next unless mount['Name'] == volume_name
              result << {
                container_name: c.info['Names'].first.split('/').last,
                node_id: node.id,
                volume_driver: mount['Driver'],
                mount_path: mount['Destination']
              }
            end
          end
        end
        result
      end

    end

  end
end
