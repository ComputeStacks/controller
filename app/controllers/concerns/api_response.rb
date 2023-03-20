module ApiResponse
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :api_obj_missing
    rescue_from ActionController::UnknownFormat, with: :unknown_format
    rescue_from ActionController::BadRequest, with: :bad_request
  end

  ##
  # =Catch missing objects
  #
  # ==Example
  #   return api_obj_missing if object.nil?
  #
  def api_obj_missing(msg = nil)
    if msg.blank?
      respond_to do |format|
        format.any(:json, :xml) { head :not_found }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: msg }, status: :not_found }
        format.xml { render xml: { errors: msg }, status: :not_found }
      end
    end
  end

  def api_obj_no_access
    api_obj_missing "Your account does not have the required permissions to access this resource."
  end

  ##
  # =Handle error responses
  #
  # ==Accepts:
  # * +e+: An array of errors
  #
  def api_obj_error(e)
    e = [e] unless e.is_a?(Array)
    respond_to do |format|
      format.json { render json: { errors: e }, status: :unprocessable_entity }
      format.xml { render xml: { errors: e }, status: :unprocessable_entity }
    end
  end

  def api_obj_destroyed
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  end

  ##
  # =Fatal error response
  #
  # ==Accepts:
  # * +e+: Ruby Standard Error Object
  # * +event_code+: String
  #
  def api_fatal_error(e, event_code)
    ExceptionAlertService.new(e, event_code).perform
    respond_to do |format|
      format.json { render json: { errors: [e.message] }, status: :internal_server_error }
      format.xml { render xml: { errors: [e.message] }, status: :internal_server_error }
    end
  end

end
