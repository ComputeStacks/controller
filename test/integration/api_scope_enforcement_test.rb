require "test_helper"
require "minitest/mock"

##
# The API's OAuth scope gate.
#
# Two of these tests are structural and matter more than the rest: every
# dispatchable action must declare a scope, and every declared scope must be one
# Doorkeeper actually knows about. Between them they make the two defects this
# suite was written for impossible to reintroduce -- an ungated action, and a
# filter that asks for a scope name no token can ever hold.
class ApiScopeEnforcementTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  # `config.eager_load` is false in test, so nothing below can walk classes or
  # subclasses without this. Without it these tests pass while inspecting almost
  # nothing.
  setup { Rails.application.eager_load! }

  ##
  # An action is a scope surface if Rails will dispatch it. That is *not* the same
  # as "it has a route": several hundred route entries (`new`/`edit` from bare
  # `resources`, plus dead CRUD verbs) name actions that do not exist, and Rails
  # raises ActionNotFound before any callback runs. Nor is it the same as "it has
  # a method": a handful of actions are template-only and reach the filter chain
  # through `default_render`.
  def dispatchable?(klass, action)
    return true if klass.action_methods.include?(action)
    Dir.glob(Rails.root.join("app/views", klass.controller_path, "#{action}.*")).any?
  end

  def api_actions
    found = []
    Rails.application.routes.routes.each do |route|
      controller = route.defaults[:controller]
      action = route.defaults[:action]
      next if controller.nil? || action.nil?
      # Descent from Api::ApplicationController is the filter, deliberately not a
      # path prefix: `api/stacks/**` and `api/system/**` inherit
      # ActionController::Base and are excluded by it anyway, while a future
      # controller that inherits from here but is routed outside /api/ would be
      # caught by it.
      klass = begin
        "#{controller}_controller".camelize.constantize
      rescue NameError
        next # routed at a controller that does not exist; nothing dispatches
      end
      next unless klass <= Api::ApplicationController
      next unless dispatchable?(klass, action)
      found << [klass, action]
    end
    found.uniq
  end

  test "every dispatchable API action declares an OAuth scope" do
    actions = api_actions

    # Guard against a vacuous pass: if the enumeration silently breaks, this
    # test must fail rather than assert nothing.
    assert_operator actions.size, :>=, 250, "route enumeration found only #{actions.size} dispatchable API actions; it is probably broken"

    undeclared = actions.reject { |klass, action| klass.api_scope_map.key?(action) }

    assert_empty undeclared.map { |klass, action| "#{klass.name}##{action}" },
      "these API actions have no api_scope declaration and will be denied to OAuth clients"
  end

  test "every declared scope is a configured Doorkeeper scope" do
    configured = Doorkeeper.config.scopes.map(&:to_s)
    offenders = []

    api_actions.map(&:first).uniq.each do |klass|
      klass.api_scope_map.each do |action, scopes|
        next if scopes.nil? # explicitly exempt
        scopes.each do |scope|
          offenders << "#{klass.name}##{action} => #{scope}" unless configured.include?(scope.to_s)
        end
      end
    end

    assert_empty offenders,
      "these declarations name a scope that is not in Doorkeeper's configured list, so no token can ever satisfy them"
  end

  test "an action with no declaration raises rather than silently passing" do
    klass = Class.new(Api::ApplicationController) do
      def self.name
        "Api::UndeclaredForTestController"
      end
    end
    controller = klass.new
    controller.define_singleton_method(:action_name) { "no_such_action" }

    assert_raises ApiScopes::UndeclaredAction do
      controller.send :authorize_api_scope!
    end
  end

  test "a token carrying the required scope is allowed" do
    get "/api/projects", as: :json, headers: bearer_headers(oauth_token("project_read"))

    assert_response :success
    refute_empty JSON.parse(response.body)["projects"]
  end

  test "a token without the required scope is refused" do
    get "/api/projects", as: :json, headers: bearer_headers(oauth_token("public"))

    assert_response :forbidden
  end

  test "a read-only token cannot write" do
    project = deployments(:project_test)

    patch "/api/projects/#{project.id}",
      params: {name: "renamed-by-a-read-token"},
      as: :json,
      headers: bearer_headers(oauth_token("project_read"))

    assert_response :forbidden
    assert_equal project.name, project.reload.name
  end

  test "the scope gate runs before resource loading" do
    # A nonexistent id: 403 rather than 404 proves the gate is not reachable only
    # for requests that happen to name a real record.
    get "/api/projects/9999999", as: :json, headers: bearer_headers(oauth_token("public"))

    assert_response :forbidden
  end

  test "HTTP Basic requests are unaffected by the scope gate" do
    get "/api/projects", as: :json, headers: @basic_auth_headers

    assert_response :success
  end

  test "actions that used to fall outside an only: list are now gated" do
    token = oauth_token("public")

    # `toggle_nat` and an ingress rule's domain list had no scope filter at all,
    # and `containers#index` is dispatchable only through its template.
    get "/api/networks/ingress_rules/9999999/domains", as: :json, headers: bearer_headers(token)
    assert_response :forbidden

    post "/api/networks/ingress_rules/9999999/toggle_nat", as: :json, headers: bearer_headers(token)
    assert_response :forbidden

    get "/api/containers", as: :json, headers: bearer_headers(token)
    assert_response :forbidden
  end

  test "a client credentials token still cannot ask for a user scope" do
    # This is what makes it safe for the scope gate to leave `current_user` alone:
    # a token with no resource owner can only ever hold `public` and `register`,
    # and the three actions reachable that way are written for a nil user.
    app = Doorkeeper::Application.find_by(name: "admin")

    post "/api/oauth/token",
      params: {scope: "project_read", grant_type: "client_credentials"},
      as: :json,
      headers: application_headers(app)

    assert_response :forbidden
  end

  ##
  # The production behaviour of a missing declaration. This is the branch plan
  # section 3.2 argues for and the one the dev/test raise hides: an OAuth caller is
  # refused, an HTTP Basic caller is deliberately let through so a forgotten
  # declaration cannot take down an integration that never used scopes, and either
  # way the condition is reported.
  test "in production an undeclared action refuses OAuth but still allows HTTP Basic" do
    original = Api::LocationsController.api_scope_map
    reported = []
    alert = Object.new
    alert.define_singleton_method(:perform) { reported << :reported }

    begin
      Api::LocationsController.api_scope_map = original.except("index")
      token = oauth_token("project_read")

      Rails.env.stub(:local?, false) do
        ExceptionAlertService.stub(:new, alert) do
          get "/api/locations", as: :json, headers: bearer_headers(token)
          assert_response :forbidden

          get "/api/locations", as: :json, headers: @basic_auth_headers
          assert_response :success
        end
      end
    ensure
      Api::LocationsController.api_scope_map = original
    end

    assert_equal 2, reported.size, "both requests should have reported the missing declaration"
  end

  private

  def application_headers(app)
    @headers.merge(
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(app.uid, app.secret)
    )
  end

  def bearer_headers(token)
    @headers.merge("Authorization" => "Bearer #{token}")
  end

  ##
  # A password-grant token for the admin user, carrying exactly +scope+.
  def oauth_token(scope)
    app = Doorkeeper::Application.find_by(name: "admin")

    post "/api/oauth/token",
      params: {
        username: user_api_credentials(:admin).username,
        password: "ve2YAixq2eh6bboq0qPVjMOC",
        scope: scope,
        grant_type: "password"
      },
      as: :json,
      headers: application_headers(app)

    assert_response :success, "could not mint a token for scope #{scope.inspect}: #{response.body}"
    JSON.parse(response.body)["access_token"]
  end
end
