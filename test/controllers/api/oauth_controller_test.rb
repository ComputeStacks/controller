require 'test_helper'

class Api::OauthControllerTest < ActionDispatch::IntegrationTest

	include ApiTestControllerBase
	include Devise::Test::IntegrationHelpers

	test 'can request oauth code' do
		sign_in users(:admin)
		oauth_application = Doorkeeper::Application.find_by(name: 'cpanel')
		assert_not_nil oauth_application

		state = SecureRandom.urlsafe_base64(32)
		cpanel_session = "cpsess12345678912"

		# Hit the auth form
		get '/api/oauth/authorize', params: {
			client_id: oauth_application.uid,
			scope: 'public',
			redirect_uri: oauth_application.redirect_uri,
			state: state,
			response_type: 'code',
			token_replace: cpanel_session
		}

		assert_response :success

		# Generate the token and be redirected back to our application
		post '/api/oauth/authorize', params: {
			client_id: oauth_application.uid,
			scope: 'public',
			redirect_uri: oauth_application.redirect_uri,
			response_type: 'code',
			code_challenge: '',
			code_challenge_method: '',
			state: state
		}

		assert_equal oauth_application.redirect_uri.gsub(":token", cpanel_session), @response.redirect_url.split("?").first

	end

end