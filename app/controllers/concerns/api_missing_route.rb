module ApiMissingRoute
  extend ActiveSupport::Concern

  def unknown_route # :nodoc:
    msg = ['Unknown API Call. Please check the documentation.']
    respond_to do |format|
      Rails.logger.warn request.request_method
      if request.request_method == 'OPTIONS'
        format.any { render plain: nil, status: :ok }
      else
        format.json { render json: {errors: msg}, status: :not_found }
        format.xml { render xml: {errors: msg}, status: :not_found  }
        format.any { render plain: msg, status: :not_found, content_type: "text/html" }
      end
    end
  end

  def unknown_format
    respond_to do |format|
      format.any { render plain: "Unknown format. Only JSON and XML are permitted.", content_type: "text/html", status: :not_acceptable }
    end
  end

  def bad_request
    msg = ['Bad Request. Please check the documentation.']
    respond_to do |format|
      Rails.logger.warn request.request_method
      if request.request_method == 'OPTIONS'
        format.any { render plain: nil, status: :ok }
      else
        format.json { render json: {errors: msg}, status: :unprocessable_entity }
        format.xml { render xml: {errors: msg}, status: :unprocessable_entity  }
        format.any { render plain: msg, content_type: "text/html", status: :unprocessable_entity }
      end
    end
  end

end