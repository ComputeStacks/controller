class Api::System::BaseController < ActionController::Base

  protect_from_forgery unless: -> { request.format.json? || request.format.xml? }

  include ApiResponse
  include ApiVersion

  respond_to :json, :xml

end
