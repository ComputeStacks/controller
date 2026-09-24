class Admin::Users::WhoisController < Admin::Users::ApplicationController
  def index
    # @sidebar_nav = 3
    # @ips = ActiveRecord::Base.connection.execute("SELECT DISTINCT(ip_addr) from audits where audits.user_id = #{params[:user_id].to_i}")
  end

  def show
    @sidebar_nav = 0
    @ip = if params[:domain]
      params[:id].tr("$", ".")
    else
      params[:id].tr("-", ".")
    end
    begin
      @ip_data = Whois::Client.new.lookup(@ip)
    rescue
      @ip_data = "Remote server error looking up #{@ip}"
    end
  end
end
