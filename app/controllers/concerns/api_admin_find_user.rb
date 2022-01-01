##
# Various flags to find a user (for admins)
#
# Available options include:
# * (nil) <-- default is just the ID of the user
# * find_by_external_id
# * find_by_email: Must base base64 encoded.
#
module ApiAdminFindUser
  extend ActiveSupport::Concern

  private

  def locate_user
    @labels = {}
    @query = {}
    find_by_attribute
    find_by_label
    @user = if !@labels.empty?
              User.find_by("labels @> ?", @labels.to_json)
            elsif !@query.empty?
              User.find_by(@query)
            else
              nil
            end
    return api_obj_missing if @user.nil?
    return api_obj_missing if @user.is_support_admin? # Just no...
  end

  def find_by_attribute
    pid = params[:user_id] ? params[:user_id] : params[:id]
    @query = if params[:find_by_external_id]
      { external_id: pid }
    elsif params[:find_by_email]
      { email: Base64.decode64(pid) }
    else
      { id: pid }
    end
  end

  def find_by_label
    pid = (params[:user_id] ? params[:user_id] : params[:id]).to_i
    if pid.zero?
      @labels = {}
      return
    end
    @labels = case params[:find_by_label]
              when 'whmcs_service_id'
                { whmcs: { service_id: pid.to_i } }
              when 'whmcs_client_id'
                { whmcs: { client_id: pid.to_i } }
              else
                {}
              end
  end

end
