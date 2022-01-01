module ApiTestControllerBase

  def before_setup
    super
    @headers = {
      'Accept' => 'application/json; api_version=65;',
      'Content-Type' => 'application/json'
    }
    @basic_auth_headers = {
      'Accept' => 'application/json; api_version=65;',
      'Content-Type' => 'application/json',
      'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(
        user_api_credentials(:admin).username,
        "ve2YAixq2eh6bboq0qPVjMOC"
      )
    }
  end

end
