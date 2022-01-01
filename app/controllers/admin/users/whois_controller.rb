class Admin::Users::WhoisController < Admin::Users::ApplicationController

  def index
    # @sidebar_nav = 3
    # @ips = ActiveRecord::Base.connection.execute("SELECT DISTINCT(ip_addr) from audits where audits.user_id = #{params[:user_id].to_i}")
  end

  def show
    @sidebar_nav = 0
    if params[:domain]
      @ip = params[:id].gsub("$",".")
    else
      @ip = params[:id].gsub("-", ".")
    end
    begin
      @ip_data = Whois::Client.new.lookup(@ip)
    rescue
      @ip_data = "Remote server error looking up #{@ip}"
    end
  end
end
