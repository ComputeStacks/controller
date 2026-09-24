class Deployments::CloudShellController < Deployments::BaseController
  def index
    unless @deployment.region.guac_available?
      redirect_to "/deployments/#{@deployment.token}", alert: "Cloud Shell Not available."
      return false
    end

    sftp = @deployment.sftp_containers.first # Only 1 per deployment.
    @shell_errors = sftp.cloud_shell_errors
    if @shell_errors.empty?
      result = sftp&.cloud_shell_token
      unless result.nil?
        redirect_to "#{@deployment.region.guac_url}/?token=#{result}", allow_other_host: true
      end
    end
  end
end
