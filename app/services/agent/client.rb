module Agent
  ##
  # Thin client for the per-node cs-agent HTTP API (the customer-metadata data
  # plane that replaces Consul KV in Phase 0a). Born small here — tenant
  # provisioning, managed-blob push, and cross-tenant /db reads — and grows as
  # coordination migrates off Consul in Phase 3.
  #
  # Transport: the agent serves PLAIN HTTP on :8500 (no mTLS — that is the
  # deferred-CA work, see D7). Privileged (admin) calls carry the per-node admin
  # Bearer stored encrypted on Node#agent_token. The address dialed is
  # Node#agent_address, NOT primary_ip: because this leg is unencrypted it can be
  # pointed at an encrypted path (e.g. Tailscale) per node, independently of the
  # Docker/SSH/HAProxy address. Unset falls back to primary_ip.
  #
  # Node resolution: a project lives on a single node (one node per region in
  # practice). Prefer resolving via an explicitly-passed region (callers that
  # already hold it — e.g. ProcessOrderService — should pass it; deriving via
  # deployment.region is computed from deployed containers and is timing-
  # sensitive). An online node is preferred; failing that, any node that is not
  # disconnected (a node in maintenance still accepts tenant and managed writes).
  # Fail fast (NotReady) if there is no such node or it has no admin token,
  # rather than emitting an empty Bearer.
  class Client
    class NotReady < StandardError; end

    AGENT_PORT = 8500
    REQUEST_TIMEOUT = 10

    # Optional changelog entity types this controller understands. The agent hides
    # them from readers that don't advertise them.
    CHANGELOG_TYPES = "node_maintenance"

    attr_reader :project, :node

    # The `high_water` of the last #changelog response: the last seq that request
    # scanned. nil before a call, or when the call failed.
    attr_reader :last_high_water

    # Build a client scoped to a node for admin/node-level calls that aren't tied to
    # a project (e.g. the changelog pull). `project` is unused by those calls, so it
    # is safe to pass nil here — resolve_node/token_hash/project.id are never reached.
    # @param node [Node]
    def self.for_node(node)
      new(nil, node: node)
    end

    # Stands in for a Deployment when only its id is known (see .for_project_id).
    ProjectRef = Struct.new(:id)

    # Build a client for a project that may no longer have a Project row -- a tenant
    # deprovision replayed after the project was destroyed. Only id-addressed calls
    # (#deprovision_tenant!) are valid on it; #provision_tenant! needs the real project.
    # @param project_id [Integer]
    # @param region [Region]
    def self.for_project_id(project_id, region:)
      new(ProjectRef.new(project_id.to_i), region: region)
    end

    # Within the block, transport errors (agent down, timeout) RAISE instead of folding
    # into the caller's failure value. AgentWorkers::PendingSyncWorker replays through the
    # ordinary live call sites, which all return a bare false, and needs to tell "the agent
    # is unreachable" (stop this region's pass) from "the agent refused this write".
    def self.raising_transport_errors
      prev = Thread.current[:agent_client_raise_transport]
      Thread.current[:agent_client_raise_transport] = true
      yield
    ensure
      Thread.current[:agent_client_raise_transport] = prev
    end

    # @param [Deployment] project
    # @param [Region, nil] region  pass when the caller already holds it
    # @param [Node, nil] node      pass to target a specific node directly
    def initialize(project, region: nil, node: nil)
      @project = project
      @node = node || resolve_node(region)
    end

    # Provision (or re-provision) the tenant: inserts the agent's tenants row +
    # creates the per-project DB. Idempotent upsert. MUST run before any
    # managed/db write for this project. @return [Boolean]
    # A success is recorded in the tenant registry (Agent::TenantRegistry).
    def provision_tenant!
      with_transport_rescue(false) do
        ok = admin_put("/v1/admin/tenants/#{project.id}", {token_hash: token_hash, status: "active"}).status.success?
        Agent::TenantRegistry.provisioned!(project.id, node.region_id) if ok
        ok
      end
    end

    # Remove the tenant mapping + per-project DB (on project trash). @return [Boolean]
    def deprovision_tenant!
      with_transport_rescue(false) do
        admin_delete("/v1/admin/tenants/#{project.id}").status.success?
      end
    end

    # Push a platform-managed blob (customer-read-only) for this project.
    # Self-healing: if the agent reports the tenant is not provisioned, provision
    # once and retry, so no call-site ordering can silently drop a managed write.
    # @param [String] path  e.g. "metadata", "ssh_keys", the sftp container name
    # @param [String] body  pre-serialized JSON
    # @param [Boolean] self_heal  false (replay) never provisions inline: the missing
    #   tenant is recorded as a pending `tenant` sync instead, so a tombstoned tenant is
    #   never recreated (Agent::PendingSync.record! ignores it while the project is deleting).
    # @return [Boolean]
    def put_managed(path, body, self_heal: true)
      with_transport_rescue(false) do
        resp = admin_put_raw("/v1/admin/projects/#{project.id}/managed/#{path}", body)
        # TODO(verify V2): confirm the agent's exact "tenant not provisioned"
        # response. 404 is the documented expectation; 409 handled defensively.
        # Pin this once the agent contract is final so a real error isn't masked.
        if [404, 409].include?(resp.status.code)
          unless self_heal
            Agent::PendingSync.record!(region: node.region_id, project: project.id, kind: "tenant",
              error: "managed write #{path}: tenant not provisioned (HTTP #{resp.status.code})")
            next false
          end
          provision_tenant!
          resp = admin_put_raw("/v1/admin/projects/#{project.id}/managed/#{path}", body)
        end
        resp.status.success?
      end
    end

    # Cross-tenant read of the customer-writable /db space (admin Bearer).
    # @return [String] response body (or "" on miss/error)
    def get_db(path)
      with_transport_rescue("") do
        resp = admin_get("/v1/admin/projects/#{project.id}/db/#{path}")
        resp.status.success? ? resp.body.to_s : ""
      end
    end

    # @return [String] response body for the whole /db space
    def all_db
      with_transport_rescue("") do
        resp = admin_get("/v1/admin/projects/#{project.id}/db")
        resp.status.success? ? resp.body.to_s : ""
      end
    end

    # Pull this node's changelog (pull-only up-channel; per-node admin Bearer). A
    # node-scoped call — no project. `since` is EXCLUSIVE (agent returns seq > since).
    # Tolerant by design: a transport error, a non-2xx, or a malformed body all yield
    # [] so a single bad node/poll never aborts the projector.
    # @param since [Integer] cursor; return entries with seq > since
    # @param entity_type [String, nil] optional server-side filter
    # @param limit [Integer]
    # Advertises `X-CS-Changelog-Types: node_maintenance`, so maintenance entries are
    # included, and records the response's `high_water` in #last_high_water.
    # @return [Array<Hash>] entries (possibly empty)
    def changelog(since:, entity_type: nil, limit: 1000)
      @last_high_water = nil
      q = {since: since, limit: limit}
      q[:entity_type] = entity_type if entity_type
      resp = http.headers("X-CS-Changelog-Types" => CHANGELOG_TYPES).get("#{base_url}/v1/admin/changelog", params: q)
      unless resp.status.success?
        report_changelog_error("HTTP #{resp.status.code}")
        return []
      end
      data = JSON.parse(resp.body.to_s)
      return [] unless data.is_a?(Hash)
      @last_high_water = Integer(data["high_water"], exception: false) if data.key?("high_water")
      Array(data["entries"])
    rescue Errno::ECONNREFUSED, SocketError, HTTP::Error, JSON::ParserError => e
      # A node in maintenance is expected to be unreachable at times (rebooting, docker
      # upgrade), so skip Sentry for it; the widened SystemEvent below still records it.
      ExceptionAlertService.new(e, "eea8970123780d42").perform unless node.maintenance
      # Also raise a SystemEvent, not just a Sentry report. The heartbeat only pings Docker
      # on primary_ip, so when the agent rides a separate path (agent_host) a break in that
      # path leaves the node reporting online while projection silently stalls — cursor
      # frozen, tasks never reaching terminal states. Sentry alone is gated on
      # SENTRY_CONFIGURED and invisible in the admin UI. Deduped 15 min per node (2 h while
      # the node is in maintenance).
      report_changelog_error("#{e.class}: #{e.message}")
      []
    end

    # --- Maintenance hold (agent >= 3.4) ---------------------------------------------
    #
    # Each returns `[status_code, body]`, body being the agent's maintenance Status (a
    # Hash) or nil when it isn't JSON. 200 = applied; 409 = our gen is behind the agent's
    # (body still carries the Status); 404 = the agent predates the maintenance API.
    # Transport errors (Errno::ECONNREFUSED, SocketError, HTTP::Error incl. timeouts) are
    # NOT rescued -- callers decide whether that is a retry or a silent miss.

    # @param timeout [Integer] seconds
    # @return [Array(Integer, Hash|nil)]
    def get_maintenance(timeout: REQUEST_TIMEOUT)
      maintenance_response(http(timeout).get("#{base_url}/v1/admin/maintenance"))
    end

    # Place (or keep) the controller hold. The agent requires a non-blank reason.
    # @return [Array(Integer, Hash|nil)]
    def put_maintenance(reason:, gen:)
      maintenance_response(admin_put("/v1/admin/maintenance", {reason: reason, gen: gen}))
    end

    # Clear the controller hold; with all: true, the node's local hold too (override).
    # @return [Array(Integer, Hash|nil)]
    # local_since_max (unix seconds, with all only) makes the override conditional: the
    # agent answers 412 and changes nothing when its local hold is newer than that.
    def delete_maintenance(gen:, all: false, local_since_max: nil)
      q = {gen: gen}
      if all
        q[:all] = 1
        q[:local_since_max] = local_since_max if local_since_max
      end
      maintenance_response(http.delete("#{base_url}/v1/admin/maintenance", params: q))
    end

    # Diagnostic reachability check for this node's agent, for `rake test_connection:agent`.
    # Unlike every other call here it reports NOTHING — no SystemEvent, no Sentry — so running
    # a connectivity check never pollutes the event log with failures the operator is already
    # looking at. Uses the changelog read because it is cheap, read-only, and exercises the
    # same address + admin Bearer the poller uses.
    #
    # Distinguishes the two failure modes that matter when a node's agent_host is wrong:
    # nothing answering at the address, versus an agent answering and rejecting our token.
    #
    # @return [Hash] {ok: Boolean, url: String, status: Integer|nil, detail: String}
    def probe
      return {ok: false, url: base_url, status: nil, detail: "no admin token on this node record"} if node.agent_token.blank?

      resp = http.get("#{base_url}/v1/admin/changelog", params: {since: 0, limit: 1})
      code = resp.status.code
      detail = case code
      when 200 then "admin bearer accepted"
      when 401, 403 then "agent answered but REJECTED our admin token — the node's admin.token_hash does not match Node#agent_token"
      when 404 then "agent answered but has no changelog endpoint — is this really a cs-agent (v3.0.0+)?"
      else "unexpected response"
      end
      {ok: resp.status.success?, url: base_url, status: code, detail: detail}
    rescue Errno::ECONNREFUSED, SocketError, HTTP::Error => e
      {ok: false, url: base_url, status: nil,
       detail: "nothing answered at this address (#{e.class}) — check the address, the node firewall, and the agent's metadata.listen_addr"}
    end

    # Report the durable projection watermark for this node: `POST /v1/admin/changelog/ack`.
    # Drives the agent's changelog prune. Monotonic on the agent side (a lower/duplicate
    # ack is ignored). Transport-tolerant — a failed ack just means we retry next pass
    # (the agent's age-fallback prune keeps the log bounded meanwhile).
    # @param seq [Integer] durable watermark
    # @return [Boolean]
    def ack_changelog(seq)
      with_transport_rescue(false) do
        admin_post("/v1/admin/changelog/ack", {seq: seq}).status.success?
      end
    end

    # --- DOWN endpoints (desired-state intent; per-node admin Bearer) ----------------
    #
    # `{host}`/`node` labels are COSMETIC — the agent doesn't validate them (a mis-addressed
    # write is silently applied), so the correctness boundary is targeting the right node's
    # endpoint + Bearer. Always build these via `Agent::Client.for_node(resolved_node)`.

    # Push the node's firewall (NAT) rules; the agent reconciles nftables on the PUT (there
    # is no firewall task and no reload trigger). `firewall_rules` is a singleton per node-DB.
    # @param host [String] cosmetic hostname label
    # @param rules [Hash] already-shaped NatRules JSON, e.g. {rules: [{proto, nat, port, dest, driver}]}
    # @return [Boolean]
    def put_firewall_rules(host, rules)
      with_transport_rescue(false) do
        admin_put("/v1/admin/nodes/#{host}/firewall_rules", rules).status.success?
      end
    end

    # Remove the node's firewall rule row. The sentinel stays latched agent-side.
    # @return [Boolean]
    def delete_firewall_rules(host)
      with_transport_rescue(false) do
        admin_delete("/v1/admin/nodes/#{host}/firewall_rules").status.success?
      end
    end

    # PUT a volume's desired-state (the agent begins scheduling backups from it). Idempotent.
    # @param project_id [String] Deployment#id, or the detached sentinel "0"
    # @param name [String] volume name (UUID)
    # @param desired [Hash] the desired-state config (must NOT carry last_backup — ignored)
    # @return [Boolean]
    def put_volume(project_id, name, desired)
      with_transport_rescue(false) do
        admin_put("/v1/admin/projects/#{project_id}/volumes/#{name}", desired).status.success?
      end
    end

    # DELETE a volume — the agent self-enqueues the idempotent `volume.trash` teardown
    # (destroys the borg repo, stops the backup container) BEFORE dropping the row.
    # @return [Boolean]
    def delete_volume(project_id, name)
      with_transport_rescue(false) do
        admin_delete("/v1/admin/projects/#{project_id}/volumes/#{name}").status.success?
      end
    end

    # Dispatch a task (`POST /v1/admin/tasks` → 202 {id, created}). The controller supplies
    # `id` (a UUID) so a retried POST is idempotent per node. Body:
    #   {id, project_id, name, node, volume, archive, audit_id, params}
    # where params = {source_volume}.
    #
    # Two refusals (return false, never POST):
    #   - a `volume.trash:` id is RESERVED for the agent — the controller must never mint it.
    #   - a node whose `datachannel_backfilled_at` is unset hasn't had its desired-state
    #     backfilled yet (first-boot ordering guard) — dispatching a backup there could land
    #     before the volume/schedule exists; refuse + alert.
    #
    # @param body [Hash] the task body (must include :id)
    # @return [String, false] the task id (truthy) on 202, false on refusal/failure.
    def create_task(body)
      with_transport_rescue(false) do
        id = (body[:id] || body["id"]).to_s
        if id.start_with?("volume.trash:")
          Rails.logger.warn("Agent::Client refusing reserved task id #{id}")
          next false
        end
        if @node.datachannel_backfilled_at.nil?
          report_unbackfilled_dispatch(body)
          next false
        end

        resp = admin_post("/v1/admin/tasks", body)
        next false unless resp.status.success?

        parsed = begin
          JSON.parse(resp.body.to_s)
        rescue JSON::ParserError
          {}
        end
        parsed["id"].presence || id.presence || true
      end
    end

    private

    def maintenance_response(resp)
      body = begin
        parsed = JSON.parse(resp.body.to_s)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end
      [resp.status.code, body]
    end

    # A DOWN task aimed at a node whose desired-state hasn't been backfilled yet is dropped
    # (the sentinel is unset). Surface it, deduped to once per 15 min per node so the boot
    # window is observable without alert spam. (Mirrors report_changelog_error.)
    def report_unbackfilled_dispatch(body)
      Rails.logger.warn("Agent::Client refusing task dispatch to un-backfilled node #{@node&.id}")
      msg = "cs-agent task refused: node #{@node&.label} has no datachannel backfill yet"
      return if SystemEvent.where("message = ? AND created_at > ?", msg, 15.minutes.ago).exists?
      SystemEvent.create!(message: msg, log_level: "warn",
        data: {"node_id" => @node&.id, "task" => (body[:name] || body["name"]), "volume" => (body[:volume] || body["volume"])},
        event_code: "f2c1b8a90d3e4756")
    end

    # A persistently non-2xx changelog leaves the node's cursor un-advanced and the
    # channel silently stalled. Surface it as a SystemEvent, deduped to once per
    # 15 min per node so a wedged node is observable without alert spam. A node in
    # maintenance is widened to 2 h: it is expected to drop off while it is worked on.
    def report_changelog_error(detail)
      Rails.logger.warn("agent changelog error node=#{node.id} #{detail}")
      # Node id in the message, not only in the data: labels carry no uniqueness constraint,
      # and the dedupe below matches on the message — two nodes sharing a label would suppress
      # each other's events forever. agent_address is recorded because this event is the
      # primary signal that a node's configured agent host is wrong, and neither an "HTTP 404"
      # detail nor a read timeout says which address was dialed.
      msg = "cs-agent changelog error on #{node.label} [node #{node.id}] (#{detail})"
      window = node.maintenance ? 2.hours : 15.minutes
      return if SystemEvent.where("message = ? AND created_at > ?", msg, window.ago).exists?
      SystemEvent.create!(message: msg, log_level: "warn",
        data: {"node_id" => node.id, "agent_address" => node.agent_address, "detail" => detail},
        event_code: "7dc84225816362c8")
    end

    # Run an agent request, converting transport failures (agent down / timeout)
    # into a logged, non-fatal `failure` value rather than aborting the caller
    # (deploy / order / refresh). Mirrors the old KV callers' tolerance.
    def with_transport_rescue(failure)
      yield
    rescue Errno::ECONNREFUSED, SocketError, HTTP::Error => e
      raise if Thread.current[:agent_client_raise_transport]
      ExceptionAlertService.new(e, "b7e3d9c1a4f60582").perform
      failure
    end

    # token_hash the agent stores/compares against — sha256 of the customer
    # Bearer (consul_auth_key).
    # TODO(verify V3): confirm the agent compares lowercase hex of raw SHA-256 of
    # the raw token string (not base64, not salted). Must match exactly or every
    # customer Bearer fails auth.
    def token_hash
      Digest::SHA256.hexdigest(project.consul_auth_key.to_s)
    end

    # Prefer an online node; else any node that isn't disconnected -- a node in
    # maintenance is reachable and accepts tenant/managed writes, and dropping them
    # for the length of a maintenance window would lose them.
    # @return [Node]
    def resolve_node(region)
      region ||= project&.region
      nodes = region&.nodes
      n = nodes&.online&.first || nodes&.where(disconnected: false)&.first
      raise NotReady, "no reachable node for project #{project&.id}" if n.nil?
      raise NotReady, "node #{n.id} has no agent_token" if n.agent_token.blank?
      n
    end

    def base_url
      "http://#{node.agent_address}:#{AGENT_PORT}"
    end

    def http(timeout = REQUEST_TIMEOUT)
      HTTP.timeout(timeout).headers(
        "Authorization" => "Bearer #{node.agent_token}",
        "Accept" => "application/json"
      )
    end

    def admin_put(path, json)
      http.headers("Content-Type" => "application/json").put("#{base_url}#{path}", json: json)
    end

    def admin_post(path, json)
      http.headers("Content-Type" => "application/json").post("#{base_url}#{path}", json: json)
    end

    def admin_put_raw(path, body)
      http.headers("Content-Type" => "application/json").put("#{base_url}#{path}", body: body)
    end

    def admin_delete(path)
      http.delete("#{base_url}#{path}")
    end

    def admin_get(path)
      http.get("#{base_url}#{path}")
    end
  end
end
