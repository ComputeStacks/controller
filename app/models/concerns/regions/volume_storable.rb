module Regions
  module VolumeStorable
    extend ActiveSupport::Concern

    ##
    # Determine usage for a given region
    #
    # For clustered storage driver, it is expected that
    # the region driver will provide a single array for all usage.
    #
    # With non-clustered storage, each node will present it's usage.
    #
    # Returns:
    #       {
    #         'volume_name' => 'size in KB'
    #       }
    def volume_usage
      if has_clustered_storage?
        usage = eval("#{volume_driver}::Region").new(self).usage
        return {} if usage.empty?
        d = {}
        usage.each do |i|
          d[i[:id]] = i[:size].to_i
        end
        d
      else
        usage = {}
        nodes.online.each do |node|
          u = eval("#{volume_driver}::Node").new(node).usage
          u.each do |i|
            if usage[i[:id]].nil?
              usage[i[:id]] = i[:size].to_i
            else
              usage[i[:id]] += i[:size].to_i
            end
          end
        end
        usage
      end
    end

  end
end
