module UsersHelper

  ##
  # Determine a user's location by their IP Address
  def country_by_ip(remote_ip, format = "code")
    geoip ||= GeoIP.new(Rails.root + "lib/GeoIP.dat")
    if format == "long"
      if remote_ip != "127.0.0.1"
        country = geoip.country(remote_ip).country_name
        if country == "--"
          country = "United States"
        elsif country == "N/A"
          country = "United States"
        end
      else
        country = "United States"
      end
    else
      if remote_ip != "127.0.0.1"
        country = geoip.country(remote_ip).country_code2
        if country == "--"
          country = "US"
        end
      else
        country = "US"
      end
    end
    country
  rescue
    format == 'code' ? 'US' : 'United States'
  end

end
