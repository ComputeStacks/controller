require "test_helper"
require "tempfile"
require "rake"

##
# The manifest apply replaces the generated bootstrap.rake template that shipped with the
# provisioner. It **bootstraps** a controller and does not converge one, so these tests pin
# the properties an operator's install depends on: greenfield works, a re-run changes
# nothing, attaching a region is additive (including the billing prices nothing else
# repairs), nothing is ever destroyed, and — the point of the whole exercise — a row a human
# has already configured is left exactly as they left it, with the difference reported
# instead of applied.
class Bootstrap::ApplyServiceTest < ActiveSupport::TestCase
  ADMIN_PASSWORD = "b00tstrap-Passw0rd".freeze

  setup do
    wipe_database!
    @io = StringIO.new
  end

  ##
  # greenfield

  test "applies a greenfield manifest to an empty database" do
    recorder = apply!(greenfield_manifest)

    location = Location.find_by(name: "ams005")
    assert_not_nil location
    region = location.regions.find_by(name: "ams-005")
    assert_not_nil region
    assert_equal "bridge", region.network_driver
    assert_equal 300, region.pid_limit
    assert_equal 2500, region.ulimit_nofile_soft
    assert_equal 3000, region.ulimit_nofile_hard
    assert_equal 27, region.p_net_size
    assert_equal "10.100.1.10:3000", region.acme_server
    assert_equal "http://10.100.1.10:3100", region.loki_endpoint
    assert_equal "http://10.100.1.5:9090", region.metric_client.endpoint
    assert_equal "http://10.100.1.5:3100", region.log_client.endpoint

    node = Node.find_by(hostname: "node1001")
    assert_not_nil node
    assert node.active, "node must be active or Node.available filters it out and every order fails"
    assert_equal region, node.region
    assert_equal "10.100.1.10", node.primary_ip
    assert_nil node.agent_host, "agent_host is optional and must stay NULL when omitted"
    assert node.agent_token.present?, "the model mints the agent token; the manifest must not"

    network = region.networks.find_by(name: "ams005")
    assert_not_nil network
    assert_equal "10.100.4.0/22", network.to_net

    lb = region.load_balancer
    assert_not_nil lb
    assert_equal "app.example.com", lb.domain
    assert_equal ["10.100.1.10"], lb.ext_ip
    assert_equal ["10.100.1.10"], lb.internal_ip
    assert_equal "*:81", lb.stats_bind
    assert_equal "haproxy-stats-pw", lb.stats_password
    assert_equal certificate_bundle, lb.shared_certificate

    # settings, encrypted and plain
    assert_equal "portal.example.com", Setting.find_by(name: "hostname").value
    assert_equal "10.100.1.20", Setting.find_by(name: "registry_node").value
    assert_equal "cr.example.com", Setting.find_by(name: "cr_le").value

    # dns: the api key/secret must round-trip through Secret, or DNS dies silently
    driver = ProductModule.find_by(name: "dns").primary
    assert_not_nil driver
    assert_equal "Pdns", driver.module_name
    assert_equal "pdns-api-key", Secret.decrypt!(driver.api_key)
    assert_equal "pdns-api-secret", Secret.decrypt!(driver.api_secret)
    assert_equal "master", driver.settings.dig("config", "zone_type")
    assert_equal ["ns1.example.com."], driver.settings.dig("config", "nameservers")
    zone = Dns::Zone.find_by(name: "app.example.com")
    assert_not_nil zone
    assert_equal "app.example.com.", zone.provider_ref
    assert_equal driver, zone.provision_driver

    # products, user group, prices
    assert BillingPlan.exists?
    group = UserGroup.find_by(is_default: true)
    assert_not_nil group
    assert_includes group.regions, region
    assert BillingResourcePrice.exists?
    BillingResourcePrice.find_each do |price|
      assert_includes price.regions, region, "every price must cover the only region"
    end

    assert Feature.find_by(name: "updated_cr_cert").active

    admin = User.find_by(email: "admin@example.com")
    assert_not_nil admin
    assert admin.is_admin
    assert_equal group, admin.user_group

    assert recorder.created.positive?
  end

  test "a second run of the same manifest changes nothing" do
    apply!(greenfield_manifest)

    before = snapshot
    @io = StringIO.new
    recorder = apply!(greenfield_manifest)

    assert_equal 0, recorder.created, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_equal 0, recorder.rotated, @io.string
    assert_equal 0, recorder.linked, @io.string
    assert_equal 0, recorder.warned, @io.string
    assert_equal before, snapshot
  end

  # The provisioner's roles/controller_seed/tasks/main.yml decides whether the
  # ansible task reports "changed" by grepping this run's stdout:
  #
  #   changed_when: "'0 created, 0 seeded, 0 rotated, 0 linked were applied' not in controller_seed_apply.stdout"
  #
  # Nothing else connects the two repos. Rewording the summary — "seeded" back to
  # "updated", a different separator, a different tense — makes every ansible run
  # report "changed" for ever, and no test anywhere would fail. Hence the literal.
  # `rotated` sits *inside* the substring rather than after it, because a rotation
  # is a write: appending it would leave the old string matching a run that
  # changed a credential, and ansible would report "ok" for it.
  test "the no-op summary line is byte-for-byte what the provisioner greps for" do
    apply!(greenfield_manifest)

    @io = StringIO.new
    recorder = apply!(greenfield_manifest)

    assert_equal 0, recorder.created, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_equal 0, recorder.rotated, @io.string
    assert_equal 0, recorder.linked, @io.string
    assert_includes @io.string, "0 created, 0 seeded, 0 rotated, 0 linked were applied; "
  end

  test "an existing row is reported as skipped rather than compared away silently" do
    apply!(greenfield_manifest)

    @io = StringIO.new
    apply!(greenfield_manifest)

    assert_match(/\[skip\s*\] Location ams005 \(exists, skipped\)/, @io.string)
    assert_match(/\[skip\s*\] Region ams-005 \(exists, skipped\)/, @io.string)
    assert_match(/\[skip\s*\] Node node1001 \(exists, skipped\)/, @io.string)
  end

  test "an encrypted value is not rewritten on a re-run" do
    apply!(greenfield_manifest)
    driver = ProductModule.find_by(name: "dns").primary
    lb = LoadBalancer.first
    api_key_ciphertext = driver.api_key
    cert_ciphertext = lb.cert_encrypted

    @io = StringIO.new
    apply!(greenfield_manifest)

    # Secret.encrypt! produces different ciphertext every call, so comparing the stored
    # value instead of the decrypted one would rewrite every secret on every run.
    assert_equal api_key_ciphertext, driver.reload.api_key
    assert_equal cert_ciphertext, lb.reload.cert_encrypted
  end

  test "a hostname written with a scheme is neither rewritten nor reported as drift" do
    manifest = greenfield_manifest
    manifest["settings"]["values"]["hostname"] = "https://portal.example.com"
    apply!(manifest)
    assert_equal "portal.example.com", Setting.find_by(name: "hostname").value

    # Make the row operator-owned so the second run takes the drift path, which is
    # where an un-normalised comparison would show up as a permanent false warning.
    configure_setting!("hostname", "portal.example.com")

    @io = StringIO.new
    recorder = apply!(manifest)
    assert_equal 0, recorder.updated, "Setting#set_value strips the scheme; the apply must too"
    assert_equal 0, recorder.warned, @io.string
  end

  ##
  # bootstrap, not override: an existing row is never modified

  test "an existing region and its children keep their database values" do
    apply!(greenfield_manifest)

    stale = greenfield_manifest
    region = stale["locations"][0]["regions"][0]
    region["pid_limit"] = 500
    region["acme_server"] = "10.100.9.9:3000"
    region["nodes"][0]["public_ip"] = "203.0.113.99"
    region["load_balancer"]["domain"] = "somewhere-else.example.com"
    stale["locations"][0]["fill_strategy"] = "most"

    @io = StringIO.new
    recorder = apply!(stale)

    saved = Region.find_by(name: "ams-005")
    assert_equal 300, saved.pid_limit
    assert_equal "10.100.1.10:3000", saved.acme_server
    assert_equal "least", saved.location.fill_strategy
    assert_equal "203.0.113.10", Node.find_by(hostname: "node1001").public_ip
    assert_equal "app.example.com", saved.load_balancer.domain

    assert_equal 0, recorder.created, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_match(/Region ams-005 — manifest differs from database, database wins/, @io.string)
    assert_match(/pid_limit: database 300, manifest 500/, @io.string)
    assert_match(/update your inventory or change it in the UI/, @io.string)
    assert_match(/Node node1001 — manifest differs/, @io.string)
    assert_match(/LoadBalancer ams-005 — manifest differs/, @io.string)
    assert_match(/Location ams005 — manifest differs/, @io.string)
  end

  test "a node added to an existing region is still created" do
    apply!(greenfield_manifest)

    grown = greenfield_manifest
    grown["locations"][0]["regions"][0]["nodes"] << {
      "label" => "node1002",
      "hostname" => "node1002",
      "primary_ip" => "10.100.1.11",
      "public_ip" => "203.0.113.11",
      "active" => true
    }

    @io = StringIO.new
    recorder = apply!(grown)

    node = Node.find_by(hostname: "node1002")
    assert_not_nil node, @io.string
    assert_equal Region.find_by(name: "ams-005"), node.region
    assert_equal 1, recorder.created, @io.string
  end

  # apply_network returns early on an existing row, so the create path here is a
  # different branch from the one "a node added to an existing region" covers.
  test "a network added to an existing region is still created" do
    apply!(greenfield_manifest)

    grown = greenfield_manifest
    grown["locations"][0]["regions"][0]["networks"] << {
      "name" => "ams005b",
      "label" => "ams-005 second",
      "subnet" => "10.100.12.0/22",
      "is_shared" => false,
      "active" => true,
      "network_driver" => "bridge"
    }

    @io = StringIO.new
    recorder = apply!(grown)

    region = Region.find_by(name: "ams-005")
    network = region.networks.find_by(name: "ams005b")
    assert_not_nil network, @io.string
    assert_equal "10.100.12.0/22", network.to_net
    assert_equal 1, recorder.created, @io.string
    # The region's original network is untouched, not replaced.
    assert_equal "10.100.4.0/22", region.networks.find_by(name: "ams005").to_net
  end

  test "an existing network's subnet is reported, never changed" do
    apply!(greenfield_manifest)

    changed = greenfield_manifest
    changed["locations"][0]["regions"][0]["networks"][0]["subnet"] = "10.100.16.0/22"

    @io = StringIO.new
    recorder = apply!(changed)

    assert_equal "10.100.4.0/22", Region.first.networks.find_by(name: "ams005").to_net
    assert_equal 0, recorder.updated, @io.string
    assert_match(%r{subnet: database "10\.100\.4\.0/22", manifest "10\.100\.16\.0/22"}, @io.string)
  end

  test "an existing dns driver is never reconfigured and its drift is reported" do
    apply!(greenfield_manifest)
    driver_id = ProductModule.find_by(name: "dns").primary.id
    region_id = Region.first.id

    moved = greenfield_manifest
    moved["dns"]["driver"]["endpoint"] = "http://10.100.9.9:8081/api/v1/servers/localhost"
    moved["dns"]["driver"]["username"] = "somebody-else"
    moved["dns"]["driver"]["settings"]["config"]["zone_type"] = "native"

    @io = StringIO.new
    recorder = apply!(moved)

    # ProvisionDriver has_many :regions, dependent: :destroy — recreating the driver here
    # would cascade-delete every region on the controller.
    assert_equal 1, ProvisionDriver.count
    assert_equal driver_id, ProductModule.find_by(name: "dns").primary.id
    driver = ProvisionDriver.find(driver_id)
    assert_equal "http://10.100.1.9:8081/api/v1/servers/localhost", driver.endpoint
    assert_equal "admin", driver.username
    assert_equal "master", driver.settings.dig("config", "zone_type")
    assert Region.exists?(region_id)

    assert_equal 0, recorder.updated, @io.string
    assert_equal 0, recorder.rotated, @io.string
    assert_match(/endpoint: database "http:\/\/10\.100\.1\.9/, @io.string)
    assert_match(/username: database "admin", manifest "somebody-else"/, @io.string)
  end

  test "a dns primary pointing at a deleted driver is repaired rather than reported" do
    apply!(greenfield_manifest)
    product_module = ProductModule.find_by(name: "dns")
    dead_driver_id = product_module.primary_id

    # A ProvisionDriver is destroyable from the admin UI and nothing nulls this
    # column out when it goes, so `primary_id` is left naming a row that is not
    # there. Raw SQL because the model's `dependent: :destroy` would take the
    # regions with it, which is not the situation being tested.
    connection = ActiveRecord::Base.connection
    connection.execute("DELETE FROM product_modules_provision_drivers WHERE provision_driver_id = #{dead_driver_id}")
    connection.execute("DELETE FROM provision_drivers WHERE id = #{dead_driver_id}")
    assert_equal dead_driver_id, ProductModule.find_by(name: "dns").primary_id

    @io = StringIO.new
    recorder = apply!(greenfield_manifest)

    driver = ProvisionDriver.find_by(endpoint: "http://10.100.1.9:8081/api/v1/servers/localhost")
    assert_not_nil driver, @io.string
    assert_not_equal dead_driver_id, driver.id
    # Repaired, not left dangling: otherwise the driver just created is wired to
    # nothing and DNS stays silently dead.
    assert_equal driver.id, ProductModule.find_by(name: "dns").primary_id, @io.string
    assert_includes ProductModule.find_by(name: "dns").provision_drivers, driver
    assert_equal 1, recorder.created, @io.string
  end

  test "a dns primary pointing at a different live driver is only reported" do
    apply!(greenfield_manifest)
    product_module = ProductModule.find_by(name: "dns")
    chosen = ProvisionDriver.create!(module_name: "Pdns", endpoint: "http://10.100.9.9:8081/api/v1/servers/localhost")
    product_module.update!(primary_id: chosen.id)

    @io = StringIO.new
    recorder = apply!(greenfield_manifest)

    assert_equal chosen.id, ProductModule.find_by(name: "dns").primary_id, @io.string
    assert_equal 0, recorder.updated, @io.string
  end

  ##
  # clients

  # These credentials are paired with the htpasswd file the provisioner writes on
  # the Prometheus/Loki host from the same variables, so they are one of the four
  # enumerated exceptions to bootstrap-only: the controller's copy has to follow a
  # rotation or the pair breaks with a green playbook run.
  test "existing metric and log client credentials are rotated" do
    apply!(greenfield_manifest)

    rotated = greenfield_manifest
    rotated["metric_clients"][0]["username"] = "prom-rotated"
    rotated["metric_clients"][0]["password"] = "prom-new-pw"
    rotated["log_clients"][0]["username"] = "loki-rotated"
    rotated["log_clients"][0]["password"] = "loki-new-pw"

    @io = StringIO.new
    recorder = apply!(rotated)

    metric = MetricClient.find_by(endpoint: "http://10.100.1.5:9090")
    log = LogClient.find_by(endpoint: "http://10.100.1.5:3100")
    assert_equal "prom-rotated", metric.username, @io.string
    assert_equal "prom-new-pw", metric.password, @io.string
    assert_equal "loki-rotated", log.username, @io.string
    assert_equal "loki-new-pw", log.password, @io.string

    assert_equal 1, MetricClient.count
    assert_equal 1, LogClient.count
    assert_equal 0, recorder.created, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_equal 4, recorder.rotated, @io.string
    assert_equal 0, recorder.warned, @io.string

    assert_match(%r{\[rotate\] MetricClient http://10\.100\.1\.5:9090 — username updated \(credential rotation\)}, @io.string)
    assert_match(%r{\[rotate\] MetricClient http://10\.100\.1\.5:9090 — password updated \(credential rotation\)}, @io.string)
    assert_match(%r{\[rotate\] LogClient http://10\.100\.1\.5:3100 — password updated \(credential rotation\)}, @io.string)
    # No value is printed, in either direction.
    assert_not_includes @io.string, "prom-new-pw"
    assert_not_includes @io.string, "loki-new-pw"
    assert_not_includes @io.string, "loki-pw"
    assert_not_includes @io.string, "prom-rotated"
  end

  # The deliberate cost of the exemption, pinned so it cannot be forgotten: a
  # credential changed on the controller is brought back to the manifest's value
  # rather than reported. That is the point — the vaulted variable is the source
  # of truth for both halves of the pair, and a controller-side edit that the
  # provisioner never saw is exactly the stale copy this is meant to repair.
  test "a client credential edited on the controller is rotated back, not warned about" do
    apply!(greenfield_manifest)
    MetricClient.find_by(endpoint: "http://10.100.1.5:9090").update!(username: "prom-by-hand")

    @io = StringIO.new
    recorder = apply!(greenfield_manifest)

    assert_equal "prom", MetricClient.find_by(endpoint: "http://10.100.1.5:9090").username, @io.string
    assert_equal 1, recorder.rotated, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_equal 0, recorder.warned, @io.string
  end

  ##
  # credential rotation — the enumerated exception to bootstrap-only

  test "the dns driver's api credentials are rotated while the rest of the row only warns" do
    apply!(greenfield_manifest)
    driver_id = ProductModule.find_by(name: "dns").primary.id

    rotated = greenfield_manifest
    rotated["dns"]["driver"]["api_key"] = "pdns-rotated-key"
    rotated["dns"]["driver"]["api_secret"] = "pdns-rotated-secret"
    rotated["dns"]["driver"]["endpoint"] = "http://10.100.9.9:8081/api/v1/servers/localhost"

    @io = StringIO.new
    recorder = apply!(rotated)

    driver = ProvisionDriver.find(driver_id)
    assert_equal "pdns-rotated-key", Secret.decrypt!(driver.api_key), @io.string
    assert_equal "pdns-rotated-secret", Secret.decrypt!(driver.api_secret), @io.string
    # Same row, non-credential field: still bootstrap-only.
    assert_equal "http://10.100.1.9:8081/api/v1/servers/localhost", driver.endpoint, @io.string

    assert_equal 2, recorder.rotated, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_match(/\[rotate\] ProvisionDriver Pdns — api_key updated \(credential rotation\)/, @io.string)
    assert_match(/\[rotate\] ProvisionDriver Pdns — api_secret updated \(credential rotation\)/, @io.string)
    assert_match(/ProvisionDriver Pdns — manifest differs from database, database wins/, @io.string)
    assert_match(/endpoint: database "http:\/\/10\.100\.1\.9/, @io.string)
    assert_not_includes @io.string, "pdns-rotated-key"
    assert_not_includes @io.string, "pdns-rotated-secret"
  end

  test "the load balancer's certificate and stats password are rotated while its domain only warns" do
    apply!(greenfield_manifest)
    renewed = build_certificate_bundle

    rotated = greenfield_manifest
    rotated["locations"][0]["regions"][0]["load_balancer"]["shared_certificate"] = renewed
    rotated["locations"][0]["regions"][0]["load_balancer"]["stats_password"] = "haproxy-rotated-pw"
    rotated["locations"][0]["regions"][0]["load_balancer"]["domain"] = "somewhere-else.example.com"

    @io = StringIO.new
    recorder = apply!(rotated)

    lb = Region.find_by(name: "ams-005").load_balancer
    assert_equal renewed, lb.shared_certificate, @io.string
    assert_equal "haproxy-rotated-pw", lb.stats_password, @io.string
    # Same row, non-credential field: still bootstrap-only.
    assert_equal "app.example.com", lb.domain, @io.string

    assert_equal 2, recorder.rotated, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_match(/\[rotate\] LoadBalancer ams-005 — stats_password updated \(credential rotation\)/, @io.string)
    assert_match(/\[rotate\] LoadBalancer ams-005 — shared_certificate updated \(credential rotation\)/, @io.string)
    assert_match(/LoadBalancer ams-005 — manifest differs from database, database wins/, @io.string)
    assert_match(/domain: database "app\.example\.com", manifest "somewhere-else\.example\.com"/, @io.string)
    assert_not_includes @io.string, "haproxy-rotated-pw"
    assert_not_includes @io.string, "BEGIN PRIVATE KEY"
  end

  test "DRY_RUN previews a rotation and writes nothing" do
    apply!(greenfield_manifest)

    rotated = greenfield_manifest
    rotated["metric_clients"][0]["password"] = "prom-new-pw"
    rotated["dns"]["driver"]["api_key"] = "pdns-rotated-key"

    @io = StringIO.new
    recorder = apply!(rotated, dry_run: true)

    assert_equal 2, recorder.rotated, @io.string
    assert_match(%r{\[rotate\] MetricClient http://10\.100\.1\.5:9090 — password updated \(credential rotation\)}, @io.string)
    assert_match(/\[rotate\] ProvisionDriver Pdns — api_key updated \(credential rotation\)/, @io.string)
    assert_includes @io.string, "0 created, 0 seeded, 2 rotated, 0 linked would be applied; "
    assert_not_includes @io.string, "prom-new-pw"
    assert_not_includes @io.string, "pdns-rotated-key"

    assert_equal "prom-pw", MetricClient.find_by(endpoint: "http://10.100.1.5:9090").password
    assert_equal "pdns-api-key", Secret.decrypt!(ProductModule.find_by(name: "dns").primary.api_key)
  end

  ##
  # readdressing — the flag-gated exception to bootstrap-only
  #
  # Three fields name an address the provisioner derives rather than an operator
  # chooses. They converge on an existing row ONLY under UPDATE_ADDRESSES=1, so
  # every test here has a twin proving that without the flag the row is left
  # exactly as it was and the difference is still only a warning.

  test "a region's acme_server is updated under UPDATE_ADDRESSES" do
    apply!(greenfield_manifest)

    moved = greenfield_manifest
    moved["locations"][0]["regions"][0]["acme_server"] = "100.64.0.10:3000"

    @io = StringIO.new
    recorder = apply!(moved, update_addresses: true)

    assert_equal "100.64.0.10:3000", Region.find_by(name: "ams-005").acme_server, @io.string
    assert_equal 1, recorder.rotated, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_equal 0, recorder.warned, @io.string
    assert_includes @io.string,
      %([readdress] Region ams-005 — acme_server: "10.100.1.10:3000" -> "100.64.0.10:3000")
  end

  test "a region's acme_server is only warned about without the flag" do
    apply!(greenfield_manifest)

    moved = greenfield_manifest
    moved["locations"][0]["regions"][0]["acme_server"] = "100.64.0.10:3000"

    @io = StringIO.new
    recorder = apply!(moved)

    assert_equal "10.100.1.10:3000", Region.find_by(name: "ams-005").acme_server, @io.string
    assert_equal 0, recorder.rotated, @io.string
    assert_equal 1, recorder.warned, @io.string
    assert_match(/acme_server: database "10\.100\.1\.10:3000", manifest "100\.64\.0\.10:3000"/, @io.string)
    assert_not_includes @io.string, "[readdress]"
  end

  test "a node's agent_host is set on an existing node under UPDATE_ADDRESSES" do
    apply!(greenfield_manifest)
    assert_nil Node.find_by(hostname: "node1001").agent_host

    tailscaled = greenfield_manifest
    tailscaled["locations"][0]["regions"][0]["nodes"][0]["agent_host"] = "node1001.tail1234.ts.net"

    @io = StringIO.new
    recorder = apply!(tailscaled, update_addresses: true)

    assert_equal "node1001.tail1234.ts.net", Node.find_by(hostname: "node1001").agent_host, @io.string
    assert_equal 1, recorder.rotated, @io.string
    assert_equal 0, recorder.warned, @io.string
    assert_includes @io.string,
      %([readdress] Node node1001 — agent_host: nil -> "node1001.tail1234.ts.net")
  end

  test "a node's agent_host is moved to a new address under UPDATE_ADDRESSES" do
    first = greenfield_manifest
    first["locations"][0]["regions"][0]["nodes"][0]["agent_host"] = "node1001.tail1234.ts.net"
    apply!(first)

    moved = greenfield_manifest
    moved["locations"][0]["regions"][0]["nodes"][0]["agent_host"] = "100.64.79.114"

    @io = StringIO.new
    recorder = apply!(moved, update_addresses: true)

    assert_equal "100.64.79.114", Node.find_by(hostname: "node1001").agent_host, @io.string
    assert_equal 1, recorder.rotated, @io.string
    assert_includes @io.string,
      %([readdress] Node node1001 — agent_host: "node1001.tail1234.ts.net" -> "100.64.79.114")
  end

  # The rollback case, and the reason agent_host does not use `attrs` like every
  # other key: the provisioner derives it pairwise and omits it entirely when the
  # node and the controller are not both on the tailnet. Under the flag an absent
  # key therefore has to mean "there is no override any more" — otherwise coming
  # off the tailnet could not be expressed in a manifest at all. Node#agent_host
  # is `allow_blank: true` and #agent_address falls back to primary_ip, so the
  # cleared node behaves exactly as it did before the column was ever set.
  test "an omitted agent_host clears the column under UPDATE_ADDRESSES" do
    first = greenfield_manifest
    first["locations"][0]["regions"][0]["nodes"][0]["agent_host"] = "node1001.tail1234.ts.net"
    apply!(first)

    @io = StringIO.new
    recorder = apply!(greenfield_manifest, update_addresses: true)

    node = Node.find_by(hostname: "node1001")
    assert_nil node.agent_host, @io.string
    assert_equal "10.100.1.10", node.agent_address, @io.string
    assert_equal 1, recorder.rotated, @io.string
    assert_equal 0, recorder.warned, @io.string
    assert_includes @io.string,
      %([readdress] Node node1001 — agent_host: "node1001.tail1234.ts.net" -> (cleared))
  end

  # Without the flag an absent key means what it means everywhere else in the
  # manifest: ignore it. It is emphatically not "set it to blank".
  test "an omitted agent_host is ignored without the flag" do
    first = greenfield_manifest
    first["locations"][0]["regions"][0]["nodes"][0]["agent_host"] = "node1001.tail1234.ts.net"
    apply!(first)

    @io = StringIO.new
    recorder = apply!(greenfield_manifest)

    assert_equal "node1001.tail1234.ts.net", Node.find_by(hostname: "node1001").agent_host, @io.string
    assert_equal 0, recorder.rotated, @io.string
    assert_equal 0, recorder.warned, @io.string
    assert_not_includes @io.string, "[readdress]"
  end

  test "a changed agent_host is only warned about without the flag" do
    apply!(greenfield_manifest)

    tailscaled = greenfield_manifest
    tailscaled["locations"][0]["regions"][0]["nodes"][0]["agent_host"] = "node1001.tail1234.ts.net"

    @io = StringIO.new
    recorder = apply!(tailscaled)

    assert_nil Node.find_by(hostname: "node1001").agent_host, @io.string
    assert_equal 0, recorder.rotated, @io.string
    assert_equal 1, recorder.warned, @io.string
    assert_match(/agent_host: database nil, manifest "node1001\.tail1234\.ts\.net"/, @io.string)
  end

  test "the dns driver's endpoint is updated under UPDATE_ADDRESSES" do
    apply!(greenfield_manifest)
    driver_id = ProductModule.find_by(name: "dns").primary.id

    moved = greenfield_manifest
    moved["dns"]["driver"]["endpoint"] = "http://100.64.0.9:8081/api/v1/servers/localhost"

    @io = StringIO.new
    recorder = apply!(moved, update_addresses: true)

    driver = ProvisionDriver.find(driver_id)
    assert_equal "http://100.64.0.9:8081/api/v1/servers/localhost", driver.endpoint, @io.string
    assert_equal 1, ProvisionDriver.count, @io.string
    assert_equal 1, recorder.rotated, @io.string
    assert_equal 0, recorder.warned, @io.string
    assert_includes @io.string,
      %([readdress] ProvisionDriver Pdns — endpoint: ) +
        %("http://10.100.1.9:8081/api/v1/servers/localhost" -> ) +
        %("http://100.64.0.9:8081/api/v1/servers/localhost")
  end

  # Everything else on those same rows is still bootstrap-only, flag or no flag.
  # The exemption is three named fields, not "the rows those fields live on".
  test "the flag does not widen to any other field on the same rows" do
    apply!(greenfield_manifest)

    changed = greenfield_manifest
    changed["locations"][0]["regions"][0]["pid_limit"] = 999
    changed["locations"][0]["regions"][0]["nodes"][0]["public_ip"] = "203.0.113.99"
    changed["dns"]["driver"]["username"] = "somebody-else"

    @io = StringIO.new
    recorder = apply!(changed, update_addresses: true)

    assert_equal 300, Region.find_by(name: "ams-005").pid_limit, @io.string
    assert_equal "203.0.113.10", Node.find_by(hostname: "node1001").public_ip, @io.string
    assert_equal "admin", ProductModule.find_by(name: "dns").primary.username, @io.string
    assert_equal 0, recorder.rotated, @io.string
    assert_equal 3, recorder.warned, @io.string
  end

  test "DRY_RUN with UPDATE_ADDRESSES previews the readdress and writes nothing" do
    first = greenfield_manifest
    first["locations"][0]["regions"][0]["nodes"][0]["agent_host"] = "node1001.tail1234.ts.net"
    apply!(first)

    moved = greenfield_manifest
    moved["locations"][0]["regions"][0]["acme_server"] = "100.64.0.10:3000"

    @io = StringIO.new
    recorder = apply!(moved, dry_run: true, update_addresses: true)

    assert_equal 2, recorder.rotated, @io.string
    assert_includes @io.string,
      %([readdress] Region ams-005 — acme_server: "10.100.1.10:3000" -> "100.64.0.10:3000")
    assert_includes @io.string,
      %([readdress] Node node1001 — agent_host: "node1001.tail1234.ts.net" -> (cleared))
    assert_includes @io.string, "0 created, 0 seeded, 2 rotated, 0 linked would be applied; "

    assert_equal "10.100.1.10:3000", Region.find_by(name: "ams-005").acme_server
    assert_equal "node1001.tail1234.ts.net", Node.find_by(hostname: "node1001").agent_host
  end

  # The flag must not make a healthy install look like it changed something —
  # ansible reads the summary line, and a permanently "changed" seed task is
  # indistinguishable from a real one.
  test "an in-sync manifest re-applied with the flag reports nothing rotated" do
    manifest = greenfield_manifest
    manifest["locations"][0]["regions"][0]["nodes"][0]["agent_host"] = "node1001.tail1234.ts.net"
    apply!(manifest, update_addresses: true)

    before = snapshot
    @io = StringIO.new
    recorder = apply!(manifest, update_addresses: true)

    assert_equal 0, recorder.created, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_equal 0, recorder.rotated, @io.string
    assert_equal 0, recorder.linked, @io.string
    assert_equal 0, recorder.warned, @io.string
    assert_equal before, snapshot
    assert_includes @io.string, "0 created, 0 seeded, 0 rotated, 0 linked were applied; "
  end

  ##
  # settings: write only what nobody has configured

  test "a setting a human configured is left alone and reported" do
    apply!(greenfield_manifest)
    configure_setting!("hostname", "human.example.com")

    @io = StringIO.new
    recorder = apply!(greenfield_manifest)

    assert_equal "human.example.com", Setting.find_by(name: "hostname").value
    assert_equal 0, recorder.updated, @io.string
    assert_equal 1, recorder.warned, @io.string
    assert_match(/Setting hostname — manifest differs from database, database wins/, @io.string)
    assert_match(/value: database "human\.example\.com", manifest "portal\.example\.com"/, @io.string)
  end

  test "a setting still at its Setting.setup! default is seeded on a live controller" do
    apply!(greenfield_manifest)
    # Setting.setup! seeds this and nothing has touched it since, so it is not
    # somebody's configuration and the manifest may write it.
    assert_equal "smtp.postmarkapp.com", Setting.find_by(name: "smtp_server").value

    seeded = greenfield_manifest
    seeded["settings"]["values"]["smtp_server"] = "smtp.internal.example.com"

    @io = StringIO.new
    recorder = apply!(seeded)

    assert_equal "smtp.internal.example.com", Setting.find_by(name: "smtp_server").value
    assert_equal 1, recorder.updated, @io.string
    assert_equal 0, recorder.warned, @io.string
  end

  test "a setting with no value at all is seeded even after somebody saved it" do
    apply!(greenfield_manifest)
    configure_setting!("google_analytics_id", "")

    seeded = greenfield_manifest
    seeded["settings"]["values"]["google_analytics_id"] = "G-12345"

    @io = StringIO.new
    apply!(seeded)

    assert_equal "G-12345", Setting.find_by(name: "google_analytics_id").value
  end

  # db/migrate/20250609233415_update_settings.rb re-points acme_email off its
  # setup sentinel with `update`, so on every *migrated* controller the row's
  # updated_at has moved with no human involved. Provenance alone would refuse
  # the operator's real ACME address for ever.
  test "a migrated acme_email still on its sentinel is seeded despite the moved timestamp" do
    apply!(greenfield_manifest)
    migrated = Setting.find_by(name: "acme_email")
    migrated.update!(value: "acme-noreply@computestacks.com")
    migrated.touch
    assert_not_equal migrated.reload.created_at, migrated.updated_at, "the migration moves updated_at"

    seeded = greenfield_manifest
    seeded["settings"]["values"]["acme_email"] = "acme@example.com"

    @io = StringIO.new
    recorder = apply!(seeded)

    assert_equal "acme@example.com", Setting.find_by(name: "acme_email").value, @io.string
    assert_equal 1, recorder.updated, @io.string
    assert_equal 0, recorder.warned, @io.string
  end

  test "an acme_email a human set is still not overwritten" do
    apply!(greenfield_manifest)
    configure_setting!("acme_email", "ops@example.com")

    seeded = greenfield_manifest
    seeded["settings"]["values"]["acme_email"] = "acme@example.com"

    @io = StringIO.new
    recorder = apply!(seeded)

    assert_equal "ops@example.com", Setting.find_by(name: "acme_email").value
    assert_equal 0, recorder.updated, @io.string
    assert_equal 1, recorder.warned, @io.string
  end

  # The same migration rewrote the `le` / `le_auto` *descriptions* only — the
  # value is still exactly what Setting.setup! wrote, but updated_at moved.
  test "a migrated le_auto still holding its setup default is seeded" do
    apply!(greenfield_manifest)
    row = Setting.find_by(name: "le_auto")
    assert_equal "t", row.value, "Setting.setup! seeds this true"
    row.update!(description: "Enable ACME scheduled job")
    row.touch
    assert_not_equal row.reload.created_at, row.updated_at

    seeded = greenfield_manifest
    seeded["settings"]["values"]["le_auto"] = "f"

    @io = StringIO.new
    recorder = apply!(seeded)

    assert_equal "f", Setting.find_by(name: "le_auto").value, @io.string
    assert_equal 1, recorder.updated, @io.string
  end

  # A Setting stores booleans as "t"/"f", so a manifest carrying YAML `false`
  # seeds correctly and then — without normalisation — never compares equal to
  # what it wrote, reporting the row as drift on every subsequent run for ever.
  test "a setting seeded from a YAML boolean is clean on the next run" do
    apply!(greenfield_manifest)
    row = Setting.find_by(name: "le_auto")
    row.update!(description: "Enable ACME scheduled job")
    row.touch

    seeded = greenfield_manifest
    seeded["settings"]["values"]["le_auto"] = false

    @io = StringIO.new
    first = apply!(seeded)
    assert_equal "f", Setting.find_by(name: "le_auto").value, @io.string
    assert_equal 1, first.updated, @io.string

    @io = StringIO.new
    second = apply!(seeded)

    assert_equal "f", Setting.find_by(name: "le_auto").value, @io.string
    assert_equal 0, second.updated, @io.string
    assert_equal 0, second.warned, @io.string
    # Skipped as configured, which it now is — but with no drift warning behind it.
    assert_match(/\[skip\s*\] Setting le_auto \(configured on this controller\)/, @io.string)
    assert_no_match(/le_auto — manifest differs/, @io.string)
    assert_no_match(/manifest false/, @io.string)
  end

  # Setting.billing_module forces signup_form off with update_column when the
  # billing module is WHMCS — no timestamp moves, so the row still *looks*
  # untouched. Seeding it would silently re-open public registration.
  test "signup_form is never seeded, and says why" do
    apply!(greenfield_manifest)
    external_billing = Setting.find_by(name: "signup_form")
    external_billing.update_column(:value, false)
    assert_equal external_billing.reload.created_at, external_billing.updated_at,
      "update_column leaves no trace in the timestamps — that is the whole problem"

    manifest = greenfield_manifest
    manifest["settings"]["values"]["signup_form"] = true

    @io = StringIO.new
    recorder = apply!(manifest)

    assert_equal "f", Setting.find_by(name: "signup_form").value, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_equal 1, recorder.warned, @io.string
    assert_match(/\[skip\s*\] Setting signup_form \(never seeded by the bootstrap\)/, @io.string)
    assert_match(/\[warn\s*\] Setting signup_form — machine-managed/, @io.string)
    assert_match(/update_column/, @io.string)
  end

  test "signup_form is not seeded on a greenfield install either" do
    manifest = greenfield_manifest
    manifest["settings"]["values"]["signup_form"] = false

    @io = StringIO.new
    apply!(manifest)

    # Setting.setup! created it at its shipped default; the manifest did not move it.
    assert_equal "t", Setting.find_by(name: "signup_form").value, @io.string
  end

  ##
  # features

  test "a feature flag a human toggled is never flipped back" do
    apply!(greenfield_manifest)
    configure_feature!("updated_cr_cert", false)

    @io = StringIO.new
    recorder = apply!(greenfield_manifest)

    assert_equal false, Feature.find_by(name: "updated_cr_cert").active
    assert_equal 0, recorder.updated, @io.string
    assert_match(/Feature updated_cr_cert — manifest differs from database, database wins/, @io.string)
    assert_match(/active: database false, manifest true/, @io.string)
  end

  test "a feature flag still at its Feature.setup! default is applied" do
    apply!(greenfield_manifest)
    assert_equal false, Feature.find_by(name: "demo").active

    manifest = greenfield_manifest
    manifest["features"]["values"]["demo"] = true

    @io = StringIO.new
    recorder = apply!(manifest)

    assert Feature.find_by(name: "demo").active
    assert_equal 1, recorder.updated, @io.string
    assert_equal 0, recorder.warned, @io.string
  end

  ##
  # attach a second region

  test "a second-region manifest is additive and leaves the first install alone" do
    apply!(greenfield_manifest)
    first_region = Region.find_by(name: "ams-005")
    settings_before = Setting.order(:id).pluck(:name, :value)
    driver_before = ProductModule.find_by(name: "dns").primary
    zones_before = Dns::Zone.order(:id).pluck(:id, :name)
    plan_count = BillingPlan.count
    price_count = BillingResourcePrice.count

    @io = StringIO.new
    apply!(attach_manifest)

    location = Location.find_by(name: "fra002")
    assert_not_nil location
    new_region = location.regions.find_by(name: "fra-002")
    assert_not_nil new_region
    assert_not_equal first_region.id, new_region.id
    assert_not_nil Node.find_by(hostname: "node2001")
    assert_not_nil new_region.networks.find_by(name: "fra002")
    assert_not_nil new_region.load_balancer
    assert_equal 2, Region.count
    assert_equal 2, Node.count

    # the whole point: every global price now covers the new region too, or every product
    # prices at 0.0 there
    assert_equal price_count, BillingResourcePrice.count, "no price rows may be created"
    BillingResourcePrice.find_each do |price|
      assert_includes price.regions, new_region, "price #{price.id} was not extended"
      assert_includes price.regions, first_region, "price #{price.id} lost its original region"
    end
    assert_equal plan_count, BillingPlan.count

    # untouched sections
    assert_equal settings_before, Setting.order(:id).pluck(:name, :value)
    assert_equal driver_before.id, ProductModule.find_by(name: "dns").primary.id
    assert_equal zones_before, Dns::Zone.order(:id).pluck(:id, :name)
    assert_includes UserGroup.find_by(is_default: true).regions, new_region
  end

  test "region-specific pricing is not widened to a new region" do
    apply!(greenfield_manifest)
    first_region = Region.find_by(name: "ams-005")
    second_region = Region.create!(name: "ams-006", location: first_region.location)

    # Everything except the storage price is made global across the two existing regions.
    storage_price = BillingResourcePrice.joins(billing_resource: :product).find_by(products: {name: "storage"})
    assert_not_nil storage_price
    BillingResourcePrice.where.not(id: storage_price.id).find_each { |p| p.regions << second_region }

    @io = StringIO.new
    apply!(attach_manifest)
    new_region = Region.find_by(name: "fra-002")

    assert_not_includes storage_price.reload.regions, new_region,
      "a price that does not cover every pre-existing region is region-specific pricing"
    BillingResourcePrice.where.not(id: storage_price.id).find_each do |price|
      assert_includes price.reload.regions, new_region
    end
    assert_match(/region-specific pricing/, @io.string)
  end

  test "a price is not extended when the phase already prices that region at the same tier" do
    apply!(greenfield_manifest)
    existing = Region.find_by(name: "ams-005")
    fresh = Region.create!(name: "ams-007", location: existing.location)

    global = BillingResourcePrice.joins(billing_resource: :product).find_by(products: {name: "backup-template-storage"})
    assert_not_nil global
    # A hand-built price for the new region only, in the same phase, currency and tier.
    duplicate = BillingResourcePrice.new(
      billing_phase: global.billing_phase,
      billing_resource: global.billing_resource,
      currency: global.currency,
      max_qty: global.max_qty,
      price: 0.5,
      regions: [fresh]
    )
    assert duplicate.save, duplicate.errors.full_messages.join("; ")

    io = StringIO.new
    recorder = Bootstrap::Recorder.new(io: io)
    Bootstrap::PriceExtender.new(recorder, Bootstrap::Writer.new(recorder), [existing.id]).perform([fresh])

    assert_not_includes global.reload.regions, fresh,
      "extending here would create two prices covering the same region+currency+max_qty, " \
      "which BillingResourcePrice forbids but the habtm insert never checks"
    assert_match(/already priced at max_qty/, io.string)
  end

  ##
  # exact-endpoint client matching

  test "a drifted metric client endpoint is a hard failure, not a silent duplicate" do
    apply!(greenfield_manifest)

    drifted = attach_manifest
    drifted["metric_clients"] = [{"endpoint" => "http://10.100.1.5:9090/"}]

    error = assert_raises(Bootstrap::Error) { apply!(drifted) }
    assert_match(%r{no MetricClient with endpoint "http://10.100.1.5:9090/"}, error.message)
    assert_equal 1, MetricClient.count, "the apply must not create a second client"
    assert_nil Region.find_by(name: "fra-002"), "the whole apply rolls back"
  end

  test "a region referencing an undeclared log client fails" do
    manifest = greenfield_manifest
    manifest["locations"][0]["regions"][0]["log_client_endpoint"] = "http://nowhere:3100"

    error = assert_raises(Bootstrap::Error) { apply!(manifest) }
    assert_match(/no LogClient with endpoint/, error.message)
    assert_match(/log_client_endpoint/, error.message)
  end

  test "a client is created only when the section says so" do
    manifest = greenfield_manifest
    manifest["metric_clients"][0].delete("create")

    assert_raises(Bootstrap::Error) { apply!(manifest) }
    assert_equal 0, MetricClient.count
  end

  ##
  # dry run

  test "DRY_RUN writes nothing and prints what would change" do
    recorder = apply!(greenfield_manifest, dry_run: true)

    assert_equal 0, Location.count
    assert_equal 0, Region.count
    assert_equal 0, Node.count
    assert_equal 0, User.count
    assert_equal 0, Setting.count
    assert recorder.created.positive?, "the diff must still describe the creates"
    assert_match(/DRY RUN/, @io.string)
    assert_match(/Location ams005/, @io.string)
    assert_match(/Node node1001/, @io.string)
  end

  test "DRY_RUN over a live install reports drift and writes nothing" do
    apply!(greenfield_manifest)
    configure_setting!("registry_node", "10.100.1.99")

    changed = greenfield_manifest
    changed["locations"][0]["regions"][0]["pid_limit"] = 500
    @io = StringIO.new
    recorder = apply!(changed, dry_run: true)

    assert_equal 0, recorder.created, @io.string
    assert_equal 0, recorder.updated, @io.string
    assert_equal 2, recorder.warned, @io.string
    assert_match(/pid_limit: database 300, manifest 500/, @io.string)
    assert_match(/value: database "10\.100\.1\.99", manifest "10\.100\.1\.20"/, @io.string)

    assert_equal 300, Region.find_by(name: "ams-005").pid_limit
    assert_equal "10.100.1.99", Setting.find_by(name: "registry_node").value
  end

  test "a secret is redacted in the printed diff" do
    apply!(greenfield_manifest, dry_run: true)
    assert_not_includes @io.string, "pdns-api-key"
    assert_not_includes @io.string, "haproxy-stats-pw"
    assert_includes @io.string, Bootstrap::Recorder::REDACTED
  end

  test "the dry-run diff shows a plaintext setting's real before/after value" do
    apply!(greenfield_manifest)

    changed = greenfield_manifest
    changed["settings"]["values"]["hostname"] = "new-portal.example.com"
    @io = StringIO.new
    recorder = apply!(changed, dry_run: true)

    # hostname is still exactly as Setting.setup! seeded it, so this is a seed, not
    # an override, and the diff must show what would be written.
    assert_equal 1, recorder.updated
    assert_includes @io.string, "portal.example.com\" → \"new-portal.example.com"
    assert_equal "portal.example.com", Setting.find_by(name: "hostname").value
  end

  test "an encrypted setting stays redacted in the dry-run diff" do
    apply!(greenfield_manifest)

    changed = greenfield_manifest
    changed["settings"]["values"]["smtp_password"] = "new-smtp-pw"
    @io = StringIO.new
    recorder = apply!(changed, dry_run: true)

    assert_equal 1, recorder.updated
    assert_not_includes @io.string, "new-smtp-pw"
    assert_match(/smtp_password.*\n.*«redacted».*«redacted»/, @io.string)
  end

  test "a plaintext setting with a credential-shaped name is redacted in the drift warning" do
    seeded = greenfield_manifest
    seeded["settings"]["values"]["belco_api_key"] = "old-belco-key"
    apply!(seeded)

    # The drift warning prints the *database's* value as well as the manifest's, so
    # the redaction has to cover it too.
    changed = seeded
    changed["settings"]["values"]["belco_api_key"] = "new-belco-key"
    @io = StringIO.new
    recorder = apply!(changed, dry_run: true)

    assert_equal 0, recorder.updated, @io.string
    assert_equal 1, recorder.warned, @io.string
    assert_not_includes @io.string, "old-belco-key"
    assert_not_includes @io.string, "new-belco-key"
    assert_match(/belco_api_key.*\n.*«redacted».*«redacted»/, @io.string)
    assert_equal "old-belco-key", Setting.find_by(name: "belco_api_key").value
  end

  ##
  # never destroy

  test "the destroy guard refuses a DELETE against a manifest-managed table" do
    location = Location.create!(name: "guarded")
    error = assert_raises(Bootstrap::Error) do
      Bootstrap::DestroyGuard.wrap { location.destroy }
    end
    assert_match(/never destroys or recreates/, error.message)
  end

  test "an existing admin user is never modified and its password is never compared" do
    apply!(greenfield_manifest)
    admin = User.find_by(email: "admin@example.com")
    digest = admin.encrypted_password

    changed = greenfield_manifest
    changed["admin_user"]["password"] = "a-completely-different-One1"
    changed["admin_user"]["fname"] = "Someone"
    @io = StringIO.new
    apply!(changed)

    assert_equal digest, admin.reload.encrypted_password
    assert_equal "Admin", admin.fname
    assert_match(/never modified by the bootstrap/, @io.string)
    assert_match(/fname: database "Admin", manifest "Someone"/, @io.string)
    assert_not_includes @io.string, "a-completely-different-One1"
  end

  test "an existing node cannot be moved between regions" do
    apply!(greenfield_manifest)

    moved = attach_manifest
    moved["locations"][0]["regions"][0]["nodes"][0]["hostname"] = "node1001"

    error = assert_raises(Bootstrap::Error) { apply!(moved) }
    assert_match(/already in region/, error.message)
  end

  test "two nodes cannot claim the same primary_ip" do
    apply!(greenfield_manifest)

    clash = attach_manifest
    clash["locations"][0]["regions"][0]["nodes"][0]["primary_ip"] = "10.100.1.10"

    error = assert_raises(Bootstrap::Error) { apply!(clash) }
    assert_match(/already belongs to node "node1001"/, error.message)
  end

  ##
  # manifest shape

  test "an unsupported schema_version is refused before anything is read" do
    error = assert_raises(Bootstrap::Error) { apply!({"schema_version" => 2}) }
    assert_match(/schema_version/, error.message)
  end

  test "an unknown key is refused rather than ignored" do
    manifest = greenfield_manifest
    manifest["locations"][0]["regions"][0]["nodes"][0]["primry_ip"] = "10.0.0.1"
    error = assert_raises(Bootstrap::Error) { apply!(manifest) }
    assert_match(/unknown key\(s\): primry_ip/, error.message)
  end

  test "a validation failure names the manifest section and key" do
    manifest = greenfield_manifest
    manifest["locations"][0]["regions"][0]["p_net_size"] = 31
    error = assert_raises(Bootstrap::Error) { apply!(manifest) }
    assert_match(/locations\[0\]\.regions\[0\]/, error.message)
    assert_match(/P net size/i, error.message)
    assert_equal 0, Region.count, "the whole apply rolls back"
  end

  test "an omitted section is not touched at all" do
    apply!(greenfield_manifest)
    hostname = Setting.find_by(name: "hostname").value

    minimal = {"schema_version" => 1}
    @io = StringIO.new
    recorder = apply!(minimal)

    assert_equal 0, recorder.created
    assert_equal 0, recorder.updated
    assert_equal hostname, Setting.find_by(name: "hostname").value
  end

  ##
  # rake wrapper

  test "the rake task exits non-zero on a bad manifest" do
    file = Tempfile.new(["manifest", ".yml"])
    file.write({"schema_version" => 99}.to_yaml)
    file.flush

    task = load_apply_task
    error = assert_raises(SystemExit) do
      capture_io { task.invoke(file.path) }
    end
    assert_equal 1, error.status
  ensure
    file&.close!
  end

  test "the rake task applies a manifest" do
    file = Tempfile.new(["manifest", ".yml"])
    file.write(greenfield_manifest.to_yaml)
    file.flush

    task = load_apply_task
    capture_io { task.invoke(file.path) }
    assert_not_nil Location.find_by(name: "ams005")
  ensure
    file&.close!
  end

  private

  def load_apply_task
    Rails.application.load_tasks unless Rake::Task.task_defined?("bootstrap:apply")
    task = Rake::Task["bootstrap:apply"]
    task.reenable
    task
  end

  # Stand in for "somebody changed this in the UI". The apply reads a row's own
  # provenance — a settings/features row whose updated_at has moved past its
  # created_at is no longer carrying the value `Setting.setup!`/`Feature.setup!`
  # gave it — so `touch` is what makes a row operator-owned, and it is applied
  # unconditionally in case the value being set is the one already stored.
  def configure_setting!(name, value)
    setting = Setting.find_by(name: name)
    assert_not_nil setting, "no Setting named #{name.inspect}"
    setting.update!(value: value)
    setting.touch
    setting
  end

  def configure_feature!(name, active)
    feature = Feature.find_by(name: name)
    assert_not_nil feature, "no Feature named #{name.inspect}"
    feature.update!(active: active)
    feature.touch
    feature
  end

  def apply!(manifest_hash, dry_run: false, update_addresses: false)
    file = Tempfile.new(["manifest", ".yml"])
    file.write(manifest_hash.to_yaml)
    file.flush
    Bootstrap::ApplyService.new(
      file.path,
      dry_run: dry_run,
      update_addresses: update_addresses,
      io: @io
    ).perform
  ensure
    file.close!
  end

  # Everything the apply could plausibly touch, in a form two runs can be compared on.
  def snapshot
    {
      locations: Location.order(:id).pluck(:id, :name, :active),
      regions: Region.order(:id).pluck(:id, :name, :location_id, :acme_server, :pid_limit),
      nodes: Node.order(:id).pluck(:id, :hostname, :primary_ip, :active, :agent_host),
      networks: Network.order(:id).pluck(:id, :name, :label, :region_id),
      load_balancers: LoadBalancer.order(:id).pluck(:id, :domain, :public_ip, :stats_bind, :stats_password),
      settings: Setting.order(:id).pluck(:id, :name, :value),
      features: Feature.order(:id).pluck(:id, :name, :active),
      drivers: ProvisionDriver.order(:id).pluck(:id, :endpoint, :module_name, :username),
      zones: Dns::Zone.order(:id).pluck(:id, :name, :provider_ref, :provision_driver_id),
      clients: MetricClient.order(:id).pluck(:id, :endpoint, :username, :password) +
        LogClient.order(:id).pluck(:id, :endpoint, :username, :password),
      prices: BillingResourcePrice.order(:id).pluck(:id, :price, :max_qty, :currency),
      price_regions: ActiveRecord::Base.connection.select_rows(
        "SELECT billing_resource_price_id, region_id FROM billing_resource_prices_regions ORDER BY 1, 2"
      ),
      groups: UserGroup.order(:id).pluck(:id, :name, :is_default),
      group_regions: ActiveRecord::Base.connection.select_rows(
        "SELECT user_group_id, region_id FROM regions_user_groups ORDER BY 1, 2"
      ),
      users: User.order(:id).pluck(:id, :email, :fname, :encrypted_password)
    }
  end

  # Greenfield means "schema only". Fixtures are loaded for every test in this suite, and
  # this runs inside the test transaction, so it rolls back with everything else.
  def wipe_database!
    connection = ActiveRecord::Base.connection
    tables = connection.tables - %w[schema_migrations ar_internal_metadata]
    connection.disable_referential_integrity do
      tables.each { |table| connection.execute(%(DELETE FROM "#{table}")) }
    end
  end

  def certificate_bundle
    @certificate_bundle ||= build_certificate_bundle
  end

  # A fresh, valid bundle every call — a rotation test needs a second one that is
  # not the one the greenfield manifest installed.
  def build_certificate_bundle
    key = OpenSSL::PKey::RSA.new(2048)
    name = OpenSSL::X509::Name.parse("/CN=*.app.example.com")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = name
    cert.issuer = name
    cert.public_key = key.public_key
    cert.not_before = Time.now.utc - 60
    cert.not_after = Time.now.utc + (365 * 24 * 60 * 60)
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    "#{cert.to_pem}#{key.to_pem}"
  end

  def greenfield_manifest
    {
      "schema_version" => 1,
      "settings" => {
        "defaults" => true,
        "values" => {
          "hostname" => "portal.example.com",
          "registry_node" => "10.100.1.20",
          "registry_base_url" => "cr.example.com",
          "registry_ssh_port" => "22",
          "cr_le" => "cr.example.com"
        }
      },
      "metric_clients" => [
        {"endpoint" => "http://10.100.1.5:9090", "create" => true, "username" => "prom", "password" => "prom-pw"}
      ],
      "log_clients" => [
        {"endpoint" => "http://10.100.1.5:3100", "create" => true, "username" => "loki", "password" => "loki-pw"}
      ],
      "dns" => {
        "driver" => {
          "module_name" => "Pdns",
          "endpoint" => "http://10.100.1.9:8081/api/v1/servers/localhost",
          "auth_type" => "static",
          "username" => "admin",
          "api_key" => "pdns-api-key",
          "api_secret" => "pdns-api-secret",
          "settings" => {
            "config" => {
              "zone_type" => "master",
              "masters" => [],
              "nameservers" => ["ns1.example.com."],
              "server" => "localhost"
            }
          }
        },
        "zones" => [{"name" => "app.example.com", "provider_ref" => "app.example.com."}]
      },
      "locations" => [
        {
          "name" => "ams005",
          "active" => true,
          "fill_strategy" => "least",
          "regions" => [
            {
              "name" => "ams-005",
              "active" => true,
              "network_driver" => "bridge",
              "p_net_size" => 27,
              "volume_backend" => "local",
              "pid_limit" => 300,
              "ulimit_nofile_soft" => 2500,
              "ulimit_nofile_hard" => 3000,
              "acme_server" => "10.100.1.10:3000",
              "loki_endpoint" => "http://10.100.1.10:3100",
              "metric_client_endpoint" => "http://10.100.1.5:9090",
              "log_client_endpoint" => "http://10.100.1.5:3100",
              "nodes" => [
                {
                  "label" => "node1001",
                  "hostname" => "node1001",
                  "primary_ip" => "10.100.1.10",
                  "public_ip" => "203.0.113.10",
                  "active" => true,
                  "ssh_port" => 22
                }
              ],
              "networks" => [
                {
                  "name" => "ams005",
                  "label" => "ams-005 shared",
                  "subnet" => "10.100.4.0/22",
                  "is_shared" => true,
                  "active" => true,
                  "network_driver" => "bridge"
                }
              ],
              "load_balancer" => {
                "label" => "ams-005 lb",
                "domain" => "app.example.com",
                "public_ip" => "203.0.113.10",
                "ext_ip" => ["10.100.1.10"],
                "internal_ip" => ["10.100.1.10"],
                "direct_connect" => false,
                "le" => false,
                "stats_bind" => "*:81",
                "stats_password" => "haproxy-stats-pw",
                "shared_certificate" => certificate_bundle
              }
            }
          ]
        }
      ],
      "products" => {"seed" => true},
      "catalog" => {"system_content" => true, "container_images" => false},
      "user_group" => {"name" => "default", "link_regions" => "all"},
      "features" => {"defaults" => true, "values" => {"updated_cr_cert" => true}},
      "admin_user" => {
        "email" => "admin@example.com",
        "password" => ADMIN_PASSWORD,
        "fname" => "Admin",
        "lname" => "Admin",
        "bypass_billing" => true
      }
    }
  end

  # What the provisioner renders when it attaches a region to a live controller: topology
  # only. No settings, no dns, no products, no admin user.
  def attach_manifest
    {
      "schema_version" => 1,
      "metric_clients" => [{"endpoint" => "http://10.100.1.5:9090"}],
      "log_clients" => [{"endpoint" => "http://10.100.1.5:3100"}],
      "locations" => [
        {
          "name" => "fra002",
          "regions" => [
            {
              "name" => "fra-002",
              "network_driver" => "bridge",
              "p_net_size" => 27,
              "volume_backend" => "local",
              "pid_limit" => 300,
              "ulimit_nofile_soft" => 2500,
              "ulimit_nofile_hard" => 3000,
              "acme_server" => "10.100.2.10:3000",
              "loki_endpoint" => "http://10.100.2.10:3100",
              "metric_client_endpoint" => "http://10.100.1.5:9090",
              "log_client_endpoint" => "http://10.100.1.5:3100",
              "nodes" => [
                {
                  "label" => "node2001",
                  "hostname" => "node2001",
                  "primary_ip" => "10.100.2.10",
                  "public_ip" => "203.0.113.20",
                  "active" => true
                }
              ],
              "networks" => [
                {"name" => "fra002", "label" => "fra-002 shared", "subnet" => "10.100.8.0/22"}
              ],
              "load_balancer" => {
                "label" => "fra-002 lb",
                "domain" => "app-fra.example.com",
                "public_ip" => "203.0.113.20",
                "ext_ip" => ["10.100.2.10"],
                "direct_connect" => false,
                "stats_bind" => "*:81",
                "stats_password" => "haproxy-stats-pw"
              }
            }
          ]
        }
      ],
      "user_group" => {"link_regions" => "all"}
    }
  end
end
