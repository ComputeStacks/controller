module LogPayload
  extend ActiveSupport::Concern

  private

  def append_info_to_payload(payload)
    super
    payload[:uuid] = request.uuid
    payload[:ip] = request.remote_ip if Feature.check('collect_user_info')
    payload[:user] = current_user.nil? ? 'anonymous' : current_user.email
    payload[:poll] = request.params['js'].to_s == 'true' || request.xhr?
    payload[:appid] = doorkeeper_token.application&.uid if doorkeeper_token
  end

end
