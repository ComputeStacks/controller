##
# In the future we can configure this to support more than just FileZilla
class Deployments::ConnectionHelperController < Deployments::BaseController

  def create
    data = case params[:id]
           when "filezilla"
             UtilityServices::FilezillaExporterService.new
           when "transmit"
             UtilityServices::TransmitExporterService.new
           else
             nil
           end
    if data.nil?
      render plain: "Unknown format", status: :unprocessable_entity
      return false
    end
    data.deployment = @deployment
    result = data.perform
    audit = Audit.create_from_object! @deployment, 'exported', request.remote_ip, current_user
    audit.update raw_data: "Generated FileZilla Config"
    send_data(result, type: data.mimme_type, filename: data.file_name, disposition: 'attachment')
  end

end
