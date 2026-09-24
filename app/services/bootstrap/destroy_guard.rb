module Bootstrap
  ##
  # Structural enforcement of the never-destroy rule.
  #
  # The apply is find-or-create only: it must never destroy or recreate a row.
  # The sharpest edge is +ProvisionDriver has_many :regions, dependent: :destroy+
  # — a "recreate the DNS driver" path would cascade-delete every region on the
  # controller, taking its nodes, networks and load balancers with it.
  #
  # Rather than trusting every call site to stay well behaved, this watches the
  # SQL the apply actually issues and raises on any DELETE against a
  # manifest-managed table.
  #
  # +features+ is deliberately NOT guarded: +Feature.setup!+ is the
  # application's own routine and prunes flags the code no longer defines. It
  # only runs when the manifest asks for the features section.
  module DestroyGuard
    GUARDED_TABLES = %w[
      billing_phases
      billing_plans
      billing_resource_prices
      billing_resource_prices_regions
      billing_resources
      dns_zones
      load_balancers
      locations
      log_clients
      metric_clients
      networks
      nodes
      product_modules
      product_modules_provision_drivers
      provision_drivers
      regions
      regions_user_groups
      settings
      user_groups
      users
    ].freeze

    DELETE_STATEMENT = /\ADELETE\s+FROM\s+"?([a-z_]+)"?/i

    def self.wrap
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        payload = args.last
        check!(payload[:sql])
      end
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    ##
    # Narrowly allow one table's deletes for the duration of a block, for a
    # delete the *application* owns and the apply merely triggers.
    #
    # The only current use is +Network#cascade_network_changes+, which prunes
    # the inactive, unattached child subnets of a parent network before laying
    # them out again. It cannot touch a network with a deployment or one that is
    # live on a node, and the apply has no way to skip it — creating the
    # region's shared network is what runs it.
    def self.permit(*tables)
      permitted.push(tables.map(&:to_s))
      yield
    ensure
      permitted.pop
    end

    def self.permitted
      Thread.current[:bootstrap_destroy_guard_permitted] ||= []
    end

    def self.permitted?(table)
      permitted.any? { |set| set.include?(table) }
    end

    def self.check!(sql)
      match = DELETE_STATEMENT.match(sql.to_s)
      return if match.nil?
      table = match[1].downcase
      return unless GUARDED_TABLES.include?(table)
      return if permitted?(table)
      raise Error.new(
        "refusing to run `DELETE FROM #{table}` — the bootstrap apply is " \
        "find-or-create only and never destroys or recreates rows"
      )
    end
  end
end
