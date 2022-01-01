module ApplicationErrors
  extend ActiveSupport::Concern

  def unknown_route
    return respond_to do |format|
      format.html {render template: 'errors/not_found', layout: current_user.nil? ? 'devise' : 'application', status: :not_found}
      format.xml {render xml: "<errors><error>page not found.</error></errors>", content_type: 'application/xml', status: :not_found}
      format.json {render json: { errors: ['page not found.'] }.to_json, content_type: 'application/json', status: :not_found}
      format.any {render plain: "page not found.", content_type: 'text/html', status: :not_found}
    end
  end

  def bad_request
    return respond_to do |format|
      format.html {render template: 'errors/not_found', layout: current_user.nil? ? 'devise' : 'application', status: :bad_request}
      format.xml {render xml: "<errors><error>page not found.</error></errors>", content_type: 'application/xml', status: :bad_request}
      format.json {render json: { errors: ['page not found.'] }.to_json, content_type: 'application/json', status: :bad_request}
      format.any {render plain: "page not found.", content_type: 'text/html', status: :bad_request}
    end
  end

  def token_error
    return respond_to do |format|
      format.html {render template: 'errors/csrf', layout: current_user.nil? ? 'devise' : 'application', status: :unprocessable_entity}
      format.xml {render xml: "<error>invalid csrf token</error>", content_type: 'application/xml', status: :unprocessable_entity}
      format.json {render json: {'error' => 'invalid csrf token'}.to_json, content_type: 'application/json', status: :unprocessable_entity}
      format.any {render plain: "invalid csrf token", content_type: 'text/html', status: :unprocessable_entity}
    end
  end

end