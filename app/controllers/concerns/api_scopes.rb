##
# =OAuth scope declarations for the API
#
# Every dispatchable action on a controller descending from
# +Api::ApplicationController+ must declare which OAuth scope a bearer token
# needs in order to call it. An action that declares nothing is *denied*, not
# allowed -- the previous arrangement (one +before_action+ lambda per controller
# with an +only:+ list) silently left every unlisted action ungated, which is how
# `toggle_nat` and friends ended up with no scope check at all.
#
# ==Declaring
#
#   api_scope read: :project_read, write: :project_write   # read => index/show
#                                                          # write => create/update/destroy
#   api_scope toggle_nat: :project_write                   # any other action, by name
#   api_scope read: [:public, :images_read]                # array == any *one* of these
#   api_scope_none :unknown_route                          # no scope check; must be explicit
#
# Declarations are inherited and refined: a subclass merges into its parent's map
# rather than replacing it, so a base controller can declare the CRUD pattern and
# a child can override a single action.
#
# ==Ordering
#
# +ApiScopes+ must be included *after* +ApiAuth+ in +Api::ApplicationController+.
# +before_action+ callbacks run in the order they were registered, and
# +authorize_api_scope!+ relies on +auth_request!+ having already rejected a
# request that presented bad HTTP Basic credentials.
#
# ==What this does not cover
#
# +Api::Stacks::BaseController+ and +Api::System::BaseController+ inherit
# +ActionController::Base+ directly and include neither +ApiAuth+ nor Doorkeeper.
# They authenticate nodes and load balancers (+ClusterAuthService+), the
# provisioner (+NODE_ENROLLMENT_TOKEN+), or trust the source IP. They are not an
# OAuth surface and are intentionally outside this concern.
module ApiScopes
  extend ActiveSupport::Concern

  ##
  # Raised in development and test when an action has no +api_scope+ declaration.
  # In production the same condition is reported to Sentry instead -- see
  # +authorize_api_scope!+.
  class UndeclaredAction < StandardError; end

  UNDECLARED_EVENT_CODE = "5f61c0b8d34ae297".freeze

  included do
    # No instance accessors: `class_attribute` would otherwise define
    # `api_scope_map` and `api_scope_map?` as public instance methods, which puts
    # them in `action_methods` and makes them look like actions.
    class_attribute :api_scope_map, instance_accessor: false, default: {}

    before_action :authorize_api_scope!
  end

  class_methods do
    ##
    # Declare the scope(s) required for one or more actions.
    #
    # ==Accepts
    # * +:read+ -- shorthand for +index+ and +show+
    # * +:write+ -- shorthand for +create+, +update+ and +destroy+
    # * any other key -- a single action name
    #
    # Values are a scope symbol, or an array of scopes meaning "any one of".
    def api_scope(**mapping)
      expanded = {}
      mapping.each do |key, scopes|
        actions = case key
                  when :read then %i[index show]
                  when :write then %i[create update destroy]
                  else [key]
                  end
        actions.each { |action| expanded[action.to_s] = Array(scopes).map(&:to_sym) }
      end
      self.api_scope_map = api_scope_map.merge(expanded)
    end

    ##
    # Declare that an action takes no scope check at all. Exemptions have to be
    # written down: the whole point of the concern is that silence means denial.
    def api_scope_none(*actions)
      self.api_scope_map = api_scope_map.merge(actions.to_h { |action| [action.to_s, nil] })
    end
  end

  private

  ##
  # The single scope gate for the API.
  #
  # The declaration check deliberately runs *before* the HTTP Basic short-circuit:
  # every API test and nearly all hand testing authenticates with Basic, so a
  # check placed after the skip would never fire and a missing declaration would
  # first show up as a production 403.
  #
  # Equally deliberately, an undeclared action in production still passes for a
  # Basic-authenticated request. Basic auth carries no scopes and is what the
  # billing and provisioning integrations use; a declaration someone forgot must
  # not be able to take those down. The dev/test raise and the route coverage
  # test in +test/integration/api_scope_enforcement_test.rb+ are what stop a
  # missing declaration from shipping.
  def authorize_api_scope!
    scope_map = self.class.api_scope_map
    return api_scope_undeclared! unless scope_map.key?(action_name)
    return if http_basic_request?

    scopes = scope_map[action_name]
    return if scopes.nil? # explicitly exempt via api_scope_none

    doorkeeper_authorize!(*scopes)
  end

  def api_scope_undeclared!
    error = UndeclaredAction.new("#{self.class.name}##{action_name} has no api_scope declaration")
    raise error if Rails.env.local?

    ExceptionAlertService.new(error, UNDECLARED_EVENT_CODE).perform
    return if http_basic_request?

    respond_to do |format|
      format.json { render json: {errors: ["Not Authorized"]}, status: :forbidden }
      format.xml { render xml: {errors: ["Not Authorized"]}, status: :forbidden }
    end
  end
end
