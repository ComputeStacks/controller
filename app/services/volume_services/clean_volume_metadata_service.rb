module VolumeServices
  class CleanVolumeMetadataService

    def perform

      Region.all.each do |region|

        # Volume Entries
        Diplomat::Kv.get_all("volumes/", consul_config(region)).each do |i|
          begin
            data = Oj.load i[:value]
            if Volume.where(name: data[:name]).exists?
              puts "[Vol-#{data[:name]}] Exists, skipping."
              next
            end
            puts "[Vol-#{data[:name]}] Removing."
            Diplomat::Kv.delete(i[:key])
          rescue => e
            puts e.message
            next
          end
        end

        # Backup Data
        Diplomat::Kv.get_all("borg/repository/", consul_config(region)).each do |i|
          begin
            data = Oj.load i[:value]
            if Volume.where(name: data[:name]).exists?
              puts "[Borg-#{data[:name]}] Exists, skipping."
              next
            end
            puts "[Borg-#{data[:name]}] Removing."
            Diplomat::Kv.delete(i[:key])
          rescue => e
            puts e.message
            next
          end
        end

      end

    end

    private

    # @param [Region] region
    def consul_config(region)
      return {} if Rails.env.test? # for test, we dont want any config here!
      return {} if region.nodes.online.empty?
      return {} if region.nodes.online.empty?
      consul_ip = region.nodes.online.first.primary_ip
      {
        http_addr: Diplomat.configuration.options.empty? ? "http://#{consul_ip}:8500" : "https://#{consul_ip}:8501",
        dc: region.name.strip.downcase,
        token: region.consul_token
      }
    end

  end
end
