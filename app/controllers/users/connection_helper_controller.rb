##
# In the future we can configure this to support more than just FileZilla
class Users::ConnectionHelperController < AuthController

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
    data.user = current_user
    result = data.perform
    send_data(result, type: data.mimme_type, filename: data.file_name, disposition: 'attachment')
  end

end
