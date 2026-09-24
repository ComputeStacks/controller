require "rake"

module Bootstrap
  ##
  # Apply a bootstrap manifest (see doc/bootstrap_manifest.md).
  #
  # **This bootstraps a controller; it does not converge one.** A row that
  # already exists is never modified — not its attributes, not its secrets. The
  # controller is edited by humans through the UI, and a manifest rendered
  # months earlier by the provisioner must not silently roll their work back
  # when the next node is deployed. Where the manifest and the database
  # disagree, the *database* wins and the difference is reported as a warning so
  # the operator can fix their inventory (or make the change in the UI).
  #
  # What still happens on a live controller, because all of it is additive:
  # creating rows that are absent, linking a new region into the default user
  # group and into the existing billing prices, and seeding +settings+ /
  # +features+ values that nobody has configured yet.
  #
  # == Exemption 1 — credential rotation, always
  #
  # Exactly four rows carry credentials the provisioner owns on *both* ends,
  # and those enumerated fields — and nothing else on those rows — are brought
  # back into step on every apply:
  #
  # * +MetricClient+ / +LogClient+: +username+, +password+
  # * the DNS +ProvisionDriver+: +api_key+, +api_secret+
  # * +LoadBalancer+: +shared_certificate+, +stats_password+
  #
  # They are machine-paired, not operator configuration: the same vaulted
  # variable renders both the manifest and the server side of the pair — the
  # htpasswd file Prometheus and Loki authenticate against, PowerDNS's
  # `api-key`, the wildcard PEM, the haproxy stats password. The provisioner
  # converges the server on every run, so leaving the controller's copy stale
  # would break the pair on a rotation while the playbook reported success.
  #
  # Every *other* field on those same rows still follows the rule above: it is
  # compared, reported as drift, and not written. See +Writer#rotate!+ and
  # doc/bootstrap_manifest.md, "Exemptions from bootstrap-only".
  #
  # == Exemption 2 — infrastructure addresses, only under UPDATE_ADDRESSES=1
  #
  # Three fields name an address the provisioner derives rather than an operator
  # chooses, and a deliberate topology change has to be expressible without
  # editing every row in the admin UI by hand — rolling tailscale onto a region
  # that is already live is the case this exists for:
  #
  # * +Region#acme_server+ (+regions[].acme_server+)
  # * +Node#agent_host+ (+regions[].nodes[].agent_host+)
  # * the DNS +ProvisionDriver#endpoint+ (+dns.driver.endpoint+)
  #
  # They are written **only** when the apply was run with +UPDATE_ADDRESSES=1+.
  # Without it the behaviour is exactly what it was before the flag existed:
  # compared, drift-warned, not written. It is opt-in rather than automatic
  # because the same write on a routine "add a node" run would silently undo an
  # address an operator moved in the UI, which is the whole reason for the
  # bootstrap-only rule.
  #
  # +agent_host+ carries one extra rule under the flag: a node entry whose key
  # is absent or null **clears** the column. The provisioner derives it pairwise
  # and omits it when the node and the controller are not both on the tailnet,
  # so "no key" is how a rollback off the tailnet is expressed. Without the flag
  # an absent key still means "ignore", as everywhere else in the manifest.
  #
  # See +Writer#readdress!+.
  #
  # Every section is optional: an attach manifest carries only +locations+ and
  # never touches settings, DNS, products or the admin user.
  #
  # The whole apply runs in one transaction with a savepoint per section, so a
  # failure anywhere leaves the database exactly as it was and the operator can
  # fix the manifest and re-run. Under +dry_run+ the outer transaction is rolled
  # back at the end, which makes the printed diff accurate (dependent creates
  # really happen) while writing nothing.
  class ApplyService
    # The order is fixed and is NOT the order of keys in the file.
    #
    # products MUST come after regions: load_products creates prices with
    # `regions: Region.all` and BillingResourcePrice validates at least one
    # region, so on an empty database it raises RecordInvalid.
    #
    # user_group MUST come after products: UserGroup belongs_to :billing_plan
    # is required.
    ORDER = %i[
      settings
      clients
      dns
      locations
      products
      catalog
      user_group
      prices
      features
      admin_user
    ].freeze

    attr_reader :manifest_path, :recorder

    def initialize(manifest_path, dry_run: false, update_addresses: false, io: $stdout)
      @manifest_path = manifest_path.to_s
      @dry_run = dry_run
      @update_addresses = update_addresses
      @io = io
    end

    def dry_run?
      @dry_run
    end

    # +UPDATE_ADDRESSES=1+. See "Exemption 2" in this class's documentation.
    def update_addresses?
      @update_addresses
    end

    # @return [Bootstrap::Recorder]
    # @raise [Bootstrap::Error]
    def perform
      @manifest = Manifest.load_file(manifest_path)
      @recorder = Recorder.new(io: @io, dry_run: dry_run?, update_addresses: update_addresses?)
      @writer = Writer.new(@recorder, update_addresses: update_addresses?)
      @preexisting_region_ids = Region.pluck(:id)
      @new_regions = []

      @recorder.header(manifest_path)

      DestroyGuard.wrap do
        ActiveRecord::Base.transaction do
          ORDER.each { |step| send(:"apply_#{step}") }
          raise ActiveRecord::Rollback if dry_run?
        end
      end

      @recorder.summary
      @recorder
    end

    private

    attr_reader :manifest, :writer

    def section(name)
      recorder.section(name)
      ActiveRecord::Base.transaction(requires_new: true) { yield }
    end

    ##
    # Is this row still carrying the value the application's own setup gave it?
    #
    # +settings+ and +features+ are the two sections whose rows are not
    # create-if-absent: +Setting.setup!+ and +Feature.setup!+ create every one of
    # them at install time, so "skip it if it exists" would mean the manifest
    # could never seed a value at all. The question for them is instead "has a
    # human configured this?", and the row answers it itself.
    #
    # The general rule is row provenance: a row whose +updated_at+ is still its
    # +created_at+ has not been written since +setup!+ created it, so it still
    # holds the +setup!+ default for its name. That consults the defaults the
    # setup actually used, per row, without keeping a second copy of the defaults
    # table here — and it stays right when a later release changes a default.
    #
    # It is a heuristic, not a proof. It is wrong in both directions, and both
    # failures are compensated for by name in +setting_unconfigured?+ and
    # +NEVER_SEED_SETTINGS+ rather than by weakening the rule:
    #
    # * FALSE NEGATIVE — a machine moved the timestamp, so an untouched row
    #   reads as configured. Migrations do this:
    #   db/migrate/20250609233415_update_settings.rb rewrites the +le+ and
    #   +le_auto+ *descriptions* and re-points +acme_email+ off its setup
    #   sentinel, all through +update+. On any controller that was migrated
    #   rather than schema-loaded, those three rows could never be seeded.
    # * FALSE POSITIVE — a machine changed the *value* without moving the
    #   timestamp, so a machine-managed row reads as unconfigured.
    #   +Setting.billing_module+ does exactly this to +signup_form+ through
    #   +update_column+.
    #
    # Features have neither problem today: nothing writes a +Feature+ outside
    # +Feature.setup!+ and the admin UI.
    def untouched_since_seeding?(record)
      return false if record.created_at.nil? || record.updated_at.nil?
      record.updated_at == record.created_at
    end

    ##
    # settings

    SETTING_KEYS = %w[defaults values].freeze

    # Settings are redacted in the printed diff when Setting#encrypted is
    # true, OR when the setting's NAME looks like it holds a credential.
    # Setting.setup! has several rows that carry credentials with
    # encrypted: false (belco_api_key, dixa_api_key), and the billing
    # module's per-provider settings only encrypt fields whose field_type
    # is "password" — a differently-shaped token (e.g. an *_api_secret or
    # *_token field) is left in the clear. Without this second, independent
    # check an operator seeding one of those via the manifest gets the raw
    # value printed into the diff and captured in ansible logs. The same rule
    # covers the drift warning, which prints the *database's* value.
    #
    # Matches a *_key, *_secret, *_token or *_password fragment (optionally
    # prefixed with api_), anchored to a name boundary so it doesn't fire on
    # an unrelated word that merely contains one of those substrings, plus
    # anything containing "hmac". Checked against every name Setting.setup!
    # creates:
    #
    #   REDACTED (9): belco_api_key, belco_shared_secret, dixa_api_key,
    #     acme_hmac_key, monarx_api_key, monarx_api_secret, monarx_agent_key,
    #     monarx_agent_secret, smtp_password
    #     (belco_api_key and dixa_api_key are the two that were plaintext and
    #     unredacted before this pattern existed; the rest are already
    #     encrypted: true and this is a redundant second guard for them)
    #
    #   VISIBLE (everything else Setting.setup! creates): acme_directory,
    #     acme_email, acme_kid, app_name, belco, billing_address,
    #     billing_module, billing_phone, branding_img_admin, branding_img_app,
    #     branding_img_login, branding_email_logo, company_name,
    #     cs_bastion_image, cr_le, dixa, signup_form, general_support,
    #     google_analytics, google_analytics_id, hostname, le, le_auto,
    #     le_dns_sleep, monarx_active, monarx_enterprise_id,
    #     registry_base_url, registry_node, registry_selinux,
    #     registry_ssh_port, smtp_from, smtp_server, smtp_port,
    #     smtp_username, ssh_motd, webhook_billing_event,
    #     webhook_billing_usage, webhook_users
    SENSITIVE_SETTING_NAME = /(?:\A|_)(?:api_)?(?:key|secret|token|password)(?:\z|_)|hmac/i

    ##
    # Names whose *value* is placeholder-shaped: whatever the timestamp says, a
    # row still holding one of these is nobody's configuration.
    #
    # This is the fix for the provenance false negative. +acme_email+ is created
    # by `Setting.setup!` as "noreply@example.acme", and
    # db/migrate/20250609233415_update_settings.rb rewrites that one value to
    # "acme-noreply@computestacks.com" with +update+ — so on every migrated
    # controller the row's timestamps have moved apart with no human involved
    # and the manifest could otherwise never seed the operator's real ACME
    # contact address.
    SETTING_SENTINEL_VALUES = {
      "acme_email" => %w[noreply@example.acme acme-noreply@computestacks.com].freeze
    }.freeze

    ##
    # Names whose +Setting.setup!+ creation default is recorded here, for rows
    # that same migration touched in a way that moved +updated_at+ *without*
    # changing the value.
    #
    # It only rewrote their +description+, so their value is still exactly what
    # +setup!+ wrote; the timestamp rule alone would refuse them for ever. This
    # is deliberately a two-entry table of known cases, not a general defaults
    # mirror — a copy of the whole defaults table would go stale the first time
    # a release changed one, which is the thing the timestamp rule exists to
    # avoid. Values as the text column stores them (`Setting.create!(value: true)`
    # casts to "t").
    SETTING_SETUP_DEFAULTS = {
      "le" => "t",
      "le_auto" => "t"
    }.freeze

    ##
    # Names the manifest may never seed, whatever the row looks like.
    #
    # This is the fix for the provenance false positive. +signup_form+ is
    # machine-managed: +Setting.billing_module+ forces it to false through
    # +update_column+ when the billing module is WHMCS, and +update_column+
    # does not move +updated_at+. The row therefore still looks untouched, and
    # a manifest carrying `signup_form: true` would re-open public registration
    # on a controller whose signups are supposed to come from WHMCS — a change
    # nothing in the apply's output would explain. There is no timestamp
    # evidence to reason from here, so the apply refuses the name outright and
    # says why.
    NEVER_SEED_SETTINGS = {
      "signup_form" => "machine-managed: Setting.billing_module forces it off for external " \
                       "billing via update_column, which leaves no trace in the row's " \
                       "timestamps — set it in the admin UI"
    }.freeze

    def apply_settings
      cfg = manifest.child("settings")
      return if cfg.nil?
      cfg.assert_keys!(SETTING_KEYS)

      section("settings") do
        Setting.setup! if cfg.flag("defaults", true)
        cfg.pairs("values").each do |name, value|
          path = "settings.values.#{name}"
          setting = Setting.find_by(name: name)
          if setting.nil?
            raise Error.new(
              "no such setting on this controller — the manifest may only seed settings " \
              "Setting.setup! creates, never invent new ones",
              path: path
            )
          end
          apply_setting(setting, name, value, path)
        end
      end
    end

    def apply_setting(setting, name, value, path)
      desired = normalize_setting(name, value)
      label = "Setting #{name}"

      reason = NEVER_SEED_SETTINGS[name.to_s]
      unless reason.nil?
        recorder.skip(label, "never seeded by the bootstrap")
        recorder.warn(label, reason)
        return
      end

      secrets = {
        # decrypted_value returns the plaintext for both encrypted and plain
        # rows, so this is the correct comparison either way.
        "value" => Writer.secret(desired, -> { setting.decrypted_value }, ->(v) { setting.value = v })
      }
      redact = (setting.encrypted || SENSITIVE_SETTING_NAME.match?(setting.name)) ? %w[value] : []

      if setting_unconfigured?(setting)
        writer.seed!(setting, label: label, path: path, secrets: secrets, redact: redact)
      else
        writer.report_drift(
          setting,
          label: label,
          reason: "configured on this controller",
          secrets: secrets,
          redact: redact
        )
      end
    end

    # A setting nobody has configured. Three ways to qualify, in order of how
    # much they prove:
    #
    # 1. no value at all;
    # 2. the value is one of the placeholders/defaults this file names for that
    #    setting — see SETTING_SENTINEL_VALUES and SETTING_SETUP_DEFAULTS, both
    #    of which exist because a migration moved the row's updated_at without a
    #    human touching it;
    # 3. the row's own provenance says it has not been written since setup!
    #    created it.
    #
    # Names in NEVER_SEED_SETTINGS never reach here; apply_setting refuses them
    # before this is asked.
    def setting_unconfigured?(setting)
      current = setting.decrypted_value
      return true if current.blank?
      return true if Array(SETTING_SENTINEL_VALUES[setting.name]).include?(current)
      return true if SETTING_SETUP_DEFAULTS[setting.name] == current
      untouched_since_seeding?(setting)
    end

    # A Setting stores a boolean in its text column as "t" / "f" —
    # `Setting.create!(value: true)` casts that way, and `Setting#is_boolean?`
    # tests for exactly those two strings.
    BOOLEAN_SETTING_VALUES = {
      true => "t",
      false => "f",
      "true" => "t",
      "false" => "f"
    }.freeze

    # Rewrite the manifest's value into the form the model itself stores, so a
    # seeded row compares equal to the manifest on the next run. Two cases, both
    # for the same reason:
    #
    # * booleans — a manifest written with YAML `true` seeds correctly (the model
    #   casts it on save) but the comparison here is by string, so `"t"` would
    #   never equal `true` again and the row would be reported as drift on every
    #   later run. Both YAML booleans and the "true"/"false" spellings are
    #   accepted; a value already written as "t"/"f" passes through untouched.
    # * `hostname` — Setting#set_value strips the scheme and trims on save, so a
    #   manifest written with a scheme would drift for ever.
    def normalize_setting(name, value)
      boolean = BOOLEAN_SETTING_VALUES[value.is_a?(String) ? value.downcase : value]
      return boolean unless boolean.nil?
      return value unless name.to_s == "hostname"
      value.to_s.gsub("http://", "").gsub("https://", "").strip
    end

    ##
    # metric_clients / log_clients

    CLIENT_KEYS = %w[endpoint create username password].freeze

    def apply_clients
      return unless manifest.key?("metric_clients") || manifest.key?("log_clients")

      section("clients") do
        apply_client_list("metric_clients", MetricClient)
        apply_client_list("log_clients", LogClient)
      end
    end

    def apply_client_list(key, klass)
      manifest.children(key).each do |entry|
        entry.assert_keys!(CLIENT_KEYS)
        endpoint = entry.fetch!("endpoint")
        record = klass.find_by(endpoint: endpoint)

        if record.nil?
          unless entry.flag("create", false)
            raise Error.new(
              "no #{klass.name} with endpoint #{endpoint.inspect}. The endpoint is matched " \
              "exactly — a trailing slash or a changed port is a different client. Add " \
              "`create: true` to create one, or correct the endpoint; the apply will not " \
              "create a duplicate client behind your back",
              path: entry.child_path("endpoint")
            )
          end
          record = klass.new(endpoint: endpoint)
        end

        # username/password are paired with the htpasswd file the provisioner
        # writes on the Prometheus/Loki host from the same vaulted variables,
        # so they rotate rather than drift — see the credential-rotation note
        # in this class's documentation above.
        writer.create_or_report!(
          record,
          label: "#{klass.name} #{endpoint}",
          path: entry.path,
          credentials: entry.attrs(:username, :password),
          redact: %w[password]
        )
      end
    end

    def find_client!(klass, endpoint, path)
      record = klass.find_by(endpoint: endpoint)
      return record unless record.nil?
      raise Error.new(
        "no #{klass.name} with endpoint #{endpoint.inspect} — declare it under " \
        "#{(klass == MetricClient) ? "metric_clients" : "log_clients"} first",
        path: path
      )
    end

    ##
    # dns

    DNS_KEYS = %w[driver zones].freeze
    DNS_DRIVER_KEYS = %w[module_name endpoint auth_type username api_key api_secret settings].freeze
    DNS_ZONE_KEYS = %w[name provider_ref].freeze

    def apply_dns
      cfg = manifest.child("dns")
      return if cfg.nil?
      cfg.assert_keys!(DNS_KEYS)

      section("dns") do
        driver = apply_dns_driver(cfg.child("driver"))
        apply_dns_zones(cfg, driver)
      end
    end

    def apply_dns_driver(cfg)
      return nil if cfg.nil?
      cfg.assert_keys!(DNS_DRIVER_KEYS)

      module_name = cfg.fetch!("module_name")
      endpoint = cfg.fetch!("endpoint")

      # Natural key is "the controller's DNS driver", not the endpoint: an
      # operator who moved PowerDNS to a new address in the UI must keep it.
      product_module = ProductModule.find_by(name: "dns")
      driver = product_module&.primary
      driver ||= ProvisionDriver.find_by(endpoint: endpoint)
      driver ||= ProvisionDriver.new

      writer.create_or_report!(
        driver,
        label: "ProvisionDriver #{module_name}",
        path: cfg.path,
        attrs: {
          "module_name" => module_name,
          "auth_type" => cfg.value("auth_type", "static"),
          "username" => cfg.value("username"),
          "settings" => cfg.value("settings")
        },
        # The API address is derived by the provisioner, so it is readdressable
        # — but only under UPDATE_ADDRESSES=1, and only because the dns section
        # is present at all. `endpoint` is fetch!'d, so the key is always here
        # and never means "clear it".
        addresses: {"endpoint" => endpoint},
        # api_key/api_secret are the same values the provisioner renders into
        # PowerDNS's own configuration, so they rotate; module_name, auth_type,
        # username and settings do not.
        credential_secrets: {
          # ProvisionDriver#cloud_auth calls Secret.decrypt! on both columns. A
          # raw write decrypts to nil and DNS stops working with no error.
          "api_key" => Writer.secret(
            cfg.value("api_key"),
            -> { driver.api_key.blank? ? nil : ::Secret.decrypt!(driver.api_key) },
            ->(v) { driver.api_key = ::Secret.encrypt!(v) }
          ),
          "api_secret" => Writer.secret(
            cfg.value("api_secret"),
            -> { driver.api_secret.blank? ? nil : ::Secret.decrypt!(driver.api_secret) },
            ->(v) { driver.api_secret = ::Secret.encrypt!(v) }
          )
        },
        redact: %w[api_key api_secret]
      )

      apply_dns_product_module(product_module, driver, cfg)
      driver
    end

    # ProductModule is plumbing rather than operator data: it is how the rest of
    # the application finds the DNS driver. Create it when it is missing, and
    # fill in `primary_id` when it is empty — that replaces nothing a human
    # chose, and leaving it empty would mean the driver we just created is not
    # wired to anything and DNS silently does nothing. A primary that points
    # somewhere else is the operator's choice and is only reported.
    #
    # A primary pointing at a row that no longer exists is repaired the same way
    # as an empty one. There is no human choice left to override: the driver it
    # named is gone (`ProvisionDriver` is destroyable from the admin UI, and
    # nothing nulls this column out when it happens), so the pointer names
    # nothing and DNS is already dead. Leaving a dangling id in place would mean
    # the driver this apply just created stays unwired with no error anywhere.
    def apply_dns_product_module(product_module, driver, cfg)
      label = "ProductModule dns"
      if product_module.nil?
        product_module = ProductModule.new(name: "dns")
        writer.create!(product_module, label: label, path: cfg.path, attrs: {"primary_id" => driver.id})
      elsif product_module.primary_id.blank? || !ProvisionDriver.exists?(product_module.primary_id)
        writer.seed!(product_module, label: label, path: cfg.path, attrs: {"primary_id" => driver.id})
      else
        writer.report_drift(product_module, label: label, attrs: {"primary_id" => driver.id})
      end
      writer.link!(product_module.provision_drivers, driver, label: label, detail: "ProvisionDriver ##{driver.id}")
    end

    def apply_dns_zones(cfg, driver)
      cfg.children("zones").each do |entry|
        entry.assert_keys!(DNS_ZONE_KEYS)
        name = entry.fetch!("name")
        zone = Dns::Zone.find_by(name: name) || Dns::Zone.new(name: name)
        # Leave run_module_create unset: the row is created locally and no zone
        # is created on the remote nameserver. The provisioner's PowerDNS role
        # owns the actual zone.
        attrs = {"provider_ref" => entry.value("provider_ref", "#{name}.")}
        attrs["provision_driver_id"] = driver.id if driver
        writer.create_or_report!(zone, label: "Dns::Zone #{name}", path: entry.path, attrs: attrs)
      end
    end

    ##
    # locations -> regions -> nodes / networks / load balancer

    LOCATION_KEYS = %w[name active fill_strategy fill_by_qty overcommit_cpu overcommit_memory regions].freeze
    REGION_KEYS = %w[
      name active network_driver p_net_size volume_backend nfs_remote_host nfs_remote_path
      nfs_controller_ip pid_limit ulimit_nofile_soft ulimit_nofile_hard acme_server
      loki_endpoint loki_retries loki_batch_size metric_client_endpoint log_client_endpoint
      fill_to offline_window failure_count disable_oom ipv6_egress guac_url guac_key settings
      nodes networks load_balancer
    ].freeze
    NODE_KEYS = %w[
      label hostname primary_ip public_ip active ssh_port agent_host port_begin port_end
      volume_device block_read_bps block_write_bps block_read_iops block_write_iops maintenance
    ].freeze
    NETWORK_KEYS = %w[name label subnet is_shared active network_driver].freeze
    LB_KEYS = %w[
      label domain public_ip ext_ip internal_ip shared_certificate stats_bind stats_password
      direct_connect le proxy_cloudflare proxy_bunny cpus maxconn maxconn_c ssl_cache max_queue
      g_timeout_connect g_timeout_client g_timeout_server proto_alpn proto_11 proto_20 proto_23
    ].freeze

    def apply_locations
      return unless manifest.key?("locations")

      section("locations") do
        manifest.children("locations").each { |entry| apply_location(entry) }
      end
    end

    def apply_location(entry)
      entry.assert_keys!(LOCATION_KEYS)
      name = entry.fetch!("name")
      location = Location.find_by(name: name) || Location.new(name: name)
      writer.create_or_report!(
        location,
        label: "Location #{name}",
        path: entry.path,
        attrs: entry.attrs(:active, :fill_strategy, :fill_by_qty, :overcommit_cpu, :overcommit_memory)
      )
      entry.children("regions").each { |r| apply_region(location, r) }
    end

    def apply_region(location, entry)
      entry.assert_keys!(REGION_KEYS)
      name = entry.fetch!("name")
      region = location.regions.find_by(name: name)

      if region.nil?
        conflict = Region.find_by(name: name)
        unless conflict.nil?
          raise Error.new(
            "a region named #{name.inspect} already exists in location " \
            "#{conflict.location&.name.inspect}. Region names must be unique across the " \
            "controller or the manifest cannot say which one it means",
            path: entry.child_path("name")
          )
        end
        region = Region.new(name: name, location: location)
      end

      attrs = entry.attrs(
        :active, :network_driver, :p_net_size, :volume_backend, :nfs_remote_host,
        :nfs_remote_path, :nfs_controller_ip, :pid_limit, :ulimit_nofile_soft,
        :ulimit_nofile_hard, :loki_endpoint, :loki_retries, :loki_batch_size,
        :fill_to, :offline_window, :failure_count, :disable_oom, :ipv6_egress, :settings
      )
      # `attrs` omits an absent key entirely, so an acme_server the manifest does
      # not carry is never written and never cleared — the clearing rule is
      # agent_host's alone.
      addresses = entry.attrs(:acme_server)

      if entry.key?("metric_client_endpoint")
        attrs["metric_client_id"] = find_client!(MetricClient, entry.value("metric_client_endpoint"), entry.child_path("metric_client_endpoint")).id
      end
      if entry.key?("log_client_endpoint")
        attrs["log_client_id"] = find_client!(LogClient, entry.value("log_client_endpoint"), entry.child_path("log_client_endpoint")).id
      end
      if entry.key?("guac_url")
        attrs["guac_url"] = entry.value("guac_url")
      end

      created = region.new_record?
      writer.create_or_report!(
        region,
        label: "Region #{name}",
        path: entry.path,
        attrs: attrs,
        addresses: addresses,
        secrets: {
          "guac_key" => Writer.secret(
            entry.value("guac_key"),
            -> { region.guac_key },
            ->(v) { region.guac_key = v }
          )
        },
        redact: %w[guac_key]
      )
      @new_regions << region if created

      entry.children("nodes").each { |n| apply_node(region, n) }
      entry.children("networks").each { |n| apply_network(region, n) }
      apply_load_balancer(region, entry.child("load_balancer"))
    end

    def apply_node(region, entry)
      entry.assert_keys!(NODE_KEYS)
      hostname = entry.fetch!("hostname")
      primary_ip = entry.fetch!("primary_ip")

      node = Node.find_by(hostname: hostname)

      # Identity, not attributes. Neither of these can be fixed by leaving the
      # row alone: the manifest is describing a node that is somewhere else, and
      # carrying on would attach this region's configuration to the wrong box.
      ip_holder = Node.find_by(primary_ip: primary_ip)
      if ip_holder && ip_holder != node
        raise Error.new(
          "primary_ip #{primary_ip.inspect} already belongs to node " \
          "#{ip_holder.hostname.inspect}. That is inventory drift; refusing to split one node " \
          "into two rows",
          path: entry.child_path("primary_ip")
        )
      end
      if node && node.region_id != region.id
        raise Error.new(
          "node #{hostname.inspect} is already in region #{node.region&.name.inspect}. " \
          "Moving a node between regions is not something a manifest may do",
          path: entry.child_path("hostname")
        )
      end
      node ||= Node.new(hostname: hostname, region: region)

      attrs = entry.attrs(
        :ssh_port, :port_begin, :port_end, :volume_device,
        :block_read_bps, :block_write_bps, :block_read_iops, :block_write_iops, :maintenance
      )
      attrs["primary_ip"] = primary_ip
      attrs["public_ip"] = entry.fetch!("public_ip")
      attrs["label"] = entry.value("label", hostname)
      # The column defaults to false and Node.available filters on it, so a node
      # left at the default accepts no orders and every order fails with no
      # visible reason. Default it to true; set active: false to opt out.
      attrs["active"] = entry.flag("active", true)

      # Deliberately NOT entry.attrs(:agent_host): the key is always present in
      # this hash, carrying nil when the manifest omits it. Under
      # UPDATE_ADDRESSES=1 that nil clears the column, which is how a node
      # coming off the tailnet is expressed — the provisioner derives agent_host
      # pairwise and simply omits the key for a node the controller cannot reach
      # over the tailnet. Without the flag the nil is skipped like any other
      # absent key, on the create path as well as the drift comparison, so
      # nothing changes for an ordinary run.
      addresses = {"agent_host" => entry.value("agent_host").presence}

      writer.create_or_report!(
        node,
        label: "Node #{hostname}",
        path: entry.path,
        attrs: attrs,
        addresses: addresses
      )
    end

    def apply_network(region, entry)
      entry.assert_keys!(NETWORK_KEYS)
      # Network#format_network_name rewrites the name on validation; match on
      # the same normalised form or every run would create a duplicate.
      name = normalize_network_name(entry.fetch!("name"))
      subnet = entry.fetch!("subnet")

      network = region.networks.find_by(name: name)
      attrs = entry.attrs(:label, :is_shared, :active, :network_driver)
      secrets = {
        # `subnet` is a cidr column whose reader drops the prefix length, so
        # compare through to_net — the manifest's own notation. An existing
        # network's subnet is only ever *reported*: changing it needs every
        # node's docker network rebuilt.
        "subnet" => Writer.secret(subnet, -> { network.to_net }, ->(v) { network.subnet = v })
      }

      unless network.nil?
        writer.report_drift(network, label: "Network #{name}", attrs: attrs, secrets: secrets)
        return
      end

      subnet_holder = region.networks.find_by(subnet: subnet)
      unless subnet_holder.nil?
        raise Error.new(
          "subnet #{subnet} is already used by network #{subnet_holder.name.inspect} in this region",
          path: entry.child_path("subnet")
        )
      end

      network = Network.new(region: region, name: name, subnet: subnet)
      # Saving a parent network runs Network#cascade_network_changes, which lays out the
      # per-project child subnets and first prunes the inactive, unattached ones. That is
      # the application's own behaviour and the apply cannot opt out of it — creating the
      # region's shared network is what runs it — so the delete is permitted for this one
      # write and nothing else.
      DestroyGuard.permit("networks") do
        writer.create!(network, label: "Network #{name}", path: entry.path, attrs: attrs, secrets: secrets)
      end
    end

    def normalize_network_name(name)
      name.to_s.strip.downcase.gsub(/[^0-9A-Za-z]/, "")
    end

    def apply_load_balancer(region, entry)
      return if entry.nil?
      entry.assert_keys!(LB_KEYS)

      lb = region.load_balancer || LoadBalancer.new(region: region)
      ext_ip = Array(entry.fetch!("ext_ip"))

      attrs = entry.attrs(
        :label, :stats_bind, :direct_connect, :le, :proxy_cloudflare,
        :proxy_bunny, :cpus, :maxconn, :maxconn_c, :ssl_cache, :max_queue,
        :g_timeout_connect, :g_timeout_client, :g_timeout_server,
        :proto_alpn, :proto_11, :proto_20, :proto_23
      )
      attrs["domain"] = entry.fetch!("domain")
      attrs["public_ip"] = entry.fetch!("public_ip")
      attrs["ext_ip"] = ext_ip
      attrs["internal_ip"] = Array(entry.value("internal_ip", ext_ip))

      writer.create_or_report!(
        lb,
        label: "LoadBalancer #{region.name}",
        path: entry.path,
        attrs: attrs,
        # The wildcard PEM and the stats password are both rendered by the
        # provisioner, which also writes the haproxy configuration that serves
        # them; everything else about the load balancer is operator-owned and
        # only reported. A renewed certificate that never reaches the
        # controller is the most consequential of the four rotations.
        credentials: entry.attrs(:stats_password),
        credential_secrets: {
          # shared_certificate= encrypts; shared_certificate decrypts. Compare
          # through the reader or a stable certificate looks drifted every run.
          "shared_certificate" => Writer.secret(
            entry.value("shared_certificate"),
            -> { lb.shared_certificate },
            ->(v) { lb.shared_certificate = v }
          )
        },
        redact: %w[shared_certificate stats_password]
      )
    end

    ##
    # products / catalog

    def apply_products
      cfg = manifest.child("products")
      return if cfg.nil?
      cfg.assert_keys!(%w[seed])
      return unless cfg.flag("seed", true)

      section("products") do
        if BillingPlan.exists?
          recorder.skip("load_products", "a BillingPlan already exists")
        else
          run_rake!("load_products")
          recorder.note("seeded default billing plan, products and prices")
        end
      end
    end

    def apply_catalog
      cfg = manifest.child("catalog")
      return if cfg.nil?
      cfg.assert_keys!(%w[system_content container_images])

      section("catalog") do
        if cfg.flag("system_content", false)
          run_rake!("default_settings")
          recorder.note("seeded system content (blocks, image providers)")
        end
        if cfg.flag("container_images", false)
          run_rake!("load_containers")
          recorder.note("seeded container image catalog")
        end
      end
    end

    # Reuse the repository's own seed tasks rather than duplicating them here —
    # a copy would drift exactly the way the generated bootstrap.rake did.
    # `execute` (not `invoke`) so the tasks can run more than once in a process.
    #
    # All three are create-if-absent throughout and so are safe under
    # bootstrap-not-override semantics:
    #
    # * `load_products` does everything inside `if BillingPlan.first.nil?`, and
    #   `apply_products` will not even call it once a plan exists. Its one
    #   `UserGroup#update` is unreachable on a live controller — `UserGroup
    #   belongs_to :billing_plan` is required, so no group can exist while there
    #   is no plan.
    # * `default_settings` is a chain of `unless … exists?` creates plus
    #   `Setting.setup!` / `Feature.setup!`, both of which only create.
    # * `load_containers` creates and never updates.
    def run_rake!(name)
      # NOTE the leading `::`. bootstrap-sass defines Bootstrap::Rails, so a bare `Rails`
      # inside this module resolves to the gem's module, not the framework.
      ::Rails.application.load_tasks unless ::Rake::Task.task_defined?(name)
      ::Rake::Task[name].execute
    rescue ActiveRecord::RecordInvalid => e
      raise Error.new("#{name} failed — #{e.message}", path: "products/catalog")
    end

    ##
    # user_group

    def apply_user_group
      cfg = manifest.child("user_group")
      return if cfg.nil?
      cfg.assert_keys!(%w[name link_regions])

      section("user_group") do
        group = UserGroup.find_by(is_default: true)
        if group.nil?
          plan = BillingPlan.find_by(is_default: true) || BillingPlan.first
          if plan.nil?
            raise Error.new(
              "cannot create the default user group: no BillingPlan exists. Add a `products` " \
              "section, or create a billing plan first — UserGroup belongs_to :billing_plan " \
              "is required",
              path: cfg.path
            )
          end
          group = UserGroup.new(name: cfg.value("name", "default"), is_default: true, billing_plan: plan)
          writer.create!(group, label: "UserGroup #{group.name}", path: cfg.path)
        else
          # An existing default group's name, quotas and billing flags are
          # operator owned; the manifest never overwrites them.
          writer.report_drift(
            group,
            label: "UserGroup #{group.name}",
            attrs: cfg.attrs(:name)
          )
        end

        # Additive: linking the default group to a region it does not yet cover
        # creates a link, it does not replace one.
        case cfg.value("link_regions", "all").to_s
        when "all"
          Region.order(:id).each do |region|
            writer.link!(group.regions, region, label: "UserGroup #{group.name}", detail: "Region #{region.name}")
          end
        when "none"
          nil
        else
          raise Error.new("must be `all` or `none`", path: cfg.child_path("link_regions"))
        end
      end
    end

    ##
    # billing price extension
    #
    # Not gated on a manifest section: a region without prices bills every
    # product at 0.0, and nothing else repairs that.

    def apply_prices
      return if @new_regions.empty?
      section("billing prices") do
        PriceExtender.new(recorder, writer, @preexisting_region_ids).perform(@new_regions)
      end
    end

    ##
    # features

    def apply_features
      cfg = manifest.child("features")
      return if cfg.nil?
      cfg.assert_keys!(%w[defaults values])

      section("features") do
        # Feature.setup! itself stays as-is. Creating and pruning the flag set is
        # controller-owned structure, not operator data — the code decides which
        # flags exist, a human decides how they are set.
        Feature.setup! if cfg.flag("defaults", true)
        cfg.pairs("values").each do |name, active|
          path = "features.values.#{name}"
          feature = Feature.find_by(name: name)
          if feature.nil?
            raise Error.new("no such feature flag on this controller", path: path)
          end
          label = "Feature #{name}"
          attrs = {"active" => ActiveModel::Type::Boolean.new.cast(active)}

          # A flag a human has toggled is never flipped back.
          if untouched_since_seeding?(feature)
            writer.seed!(feature, label: label, path: path, attrs: attrs)
          else
            writer.report_drift(feature, label: label, reason: "toggled on this controller", attrs: attrs)
          end
        end
      end
    end

    ##
    # admin_user

    ADMIN_KEYS = %w[email password fname lname currency bypass_billing].freeze

    def apply_admin_user
      cfg = manifest.child("admin_user")
      return if cfg.nil?
      cfg.assert_keys!(ADMIN_KEYS)

      section("admin_user") do
        email = cfg.fetch!("email")
        existing = User.find_by(email: email)
        unless existing.nil?
          # Create-if-absent only. Re-applying a manifest must never be a way to
          # reset a password or re-grant admin on an existing account, so the
          # password is not even compared — only the profile fields are, and
          # only to report.
          writer.report_drift(
            existing,
            label: "User #{email}",
            reason: "exists, skipped — never modified by the bootstrap",
            attrs: cfg.attrs(:fname, :lname, :currency, :bypass_billing)
          )
          next
        end
        password = cfg.fetch!("password")
        user = User.new(
          email: email,
          fname: cfg.value("fname", "Admin"),
          lname: cfg.value("lname", "Admin"),
          currency: cfg.value("currency", ENV["CURRENCY"]),
          bypass_billing: cfg.flag("bypass_billing", true),
          is_admin: true,
          password: password,
          password_confirmation: password
        )
        user.skip_confirmation!
        unless user.save
          raise Error.from_record(user, path: cfg.path, action: "create")
        end
        recorder.create("User #{email}")
      end
    end
  end
end
