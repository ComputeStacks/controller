namespace :agent do
  desc "Phase 3 cutover: backfill each node's full desired-state (firewall + every volume) onto its cs-agent, then latch nodes.datachannel_backfilled_at. MANDATORY on first boot (agent coordination tables start empty; the sentinel gate in Agent::Client#create_task depends on it). Idempotent + resumable — safe to re-run. Set NODE_ID=<id> or NODE=<hostname> to limit the pass to one node and its volumes. Exits non-zero if any node or volume operation failed."
  task datachannel_backfill: :environment do
    # Optional single-node scope. The provisioner uses this when attaching one node to a
    # live fleet: a full-fleet pass there would re-PUT desired state to every existing node
    # for no reason, and one unrelated failure would mask the result for the node it cares
    # about. No scope set = the whole fleet, exactly as before.
    target = nil
    if ENV["NODE_ID"].present? || ENV["NODE"].present?
      target = if ENV["NODE_ID"].present?
        Node.find_by(id: ENV["NODE_ID"])
      else
        Node.find_by(hostname: ENV["NODE"])
      end
      if target.nil?
        puts "[fatal] no node matching #{ENV["NODE_ID"].present? ? "NODE_ID=#{ENV["NODE_ID"]}" : "NODE=#{ENV["NODE"]}"}"
        exit 1
      end
      puts "Scoped to node #{target.id} (#{target.label}) — the rest of the fleet is untouched.\n\n"
    end
    node_scope = target ? Node.where(id: target.id) : Node
    volume_scope = target ? target.volumes : Volume

    # Track per-node success so the sentinel is latched ONLY after a fully-successful pass
    # (firewall PUT + every volume that node owns). A single failure leaves the node
    # un-latched so a re-run retries it.
    node_ok = Hash.new(true)
    node_seen = {}
    # Nodes that actually went through the firewall pass. A node that only turns up in the
    # volume loop (it came online mid-run) must NOT latch: its firewall desired-state was
    # never pushed, so "backfilled" would be a lie until the next ingress change.
    firewall_seen = {}

    # --- Firewall rules per online node -------------------------------------------------
    node_scope.online.find_each do |node|
      node_seen[node.id] = node
      firewall_seen[node.id] = true
      if node.agent_token.blank?
        puts "[skip] node #{node.id} (#{node.label}): no agent_token — re-run later"
        node_ok[node.id] = false
        next
      end
      if node.update_iptable_config!
        puts "[ok] firewall node #{node.id} (#{node.label})"
      else
        puts "[fail] firewall node #{node.id} (#{node.label})"
        node_ok[node.id] = false
      end
    rescue => e
      puts "[fail] firewall node #{node.id}: #{e.class}: #{e.message}"
      node_ok[node.id] = false
    end

    # --- Volume desired-state per volume with an online node ----------------------------
    volume_scope.find_each do |volume|
      next if volume.nodes.online.empty?
      node = volume.active_node
      # Under a node scope, only the volumes this node actually owns right now.
      next if target && node && node.id != target.id
      if node.nil?
        puts "[skip] volume #{volume.id} (#{volume.name}): no online node — re-run later"
        next
      end
      node_seen[node.id] ||= node
      if node.agent_token.blank?
        puts "[skip] volume #{volume.id} → node #{node.id}: no agent_token — re-run later"
        node_ok[node.id] = false
        next
      end
      # update_consul! PUTs this volume's desired-state to active_node (sentinel-0 for a
      # detached volume via agent_project_id). Returns the put_volume Boolean.
      if volume.update_consul!
        puts "[ok] volume #{volume.id} (#{volume.name}) → node #{node.id}"
      else
        puts "[fail] volume #{volume.id} (#{volume.name}) → node #{node.id}"
        node_ok[node.id] = false
      end
    rescue => e
      puts "[fail] volume #{volume.id}: #{e.class}: #{e.message}"
      node = (volume.active_node rescue nil)
      node_ok[node.id] = false if node
    end

    # --- Latch the sentinel for fully-successful nodes ----------------------------------
    latched = 0
    node_seen.each_value do |node|
      if node_ok[node.id] && node.agent_token.present? && firewall_seen[node.id]
        node.update_column(:datachannel_backfilled_at, Time.current)
        latched += 1
        puts "[latched] node #{node.id} (#{node.label}) datachannel_backfilled_at"
      elsif !firewall_seen[node.id]
        puts "[not-latched] node #{node.id} (#{node.label}): came online mid-pass, no firewall push — re-run to latch"
      else
        puts "[not-latched] node #{node.id} (#{node.label}): had failures — re-run to latch"
      end
    end

    puts "\nagent:datachannel_backfill done — latched #{latched}/#{node_seen.size} node(s) seen this pass"

    # --- Fleet-wide completeness gate ---------------------------------------------------
    # The count above only covers nodes this pass touched. `Node.online` excludes disconnected
    # AND maintenance nodes, so those never produce a line and never enter node_seen — without
    # this block the run ends "latched 5/5" while a sixth node stays permanently gated out of
    # backup/restore dispatch (Agent::Client#create_task refuses an un-latched node). This is
    # the operator's completeness check; do not treat the pass as done while it prints nodes.
    pending = node_scope.where(datachannel_backfilled_at: nil).order(:id)
    if pending.empty?
      puts "All #{node_scope.count} node(s) are backfilled — the #{target ? "scoped node is" : "fleet is fully"} latched."
    else
      puts "\nWARNING: #{pending.size} node(s) NOT backfilled. Backup, restore, export and"
      puts "delete dispatch stays BLOCKED for these until they latch:"
      pending.each do |node|
        reason = if node.agent_token.blank?
          "no agent_token"
        elsif node.maintenance?
          "in maintenance mode (excluded from this pass)"
        elsif node.disconnected?
          "disconnected (excluded from this pass)"
        elsif node_seen.key?(node.id)
          "failures during this pass"
        else
          "not seen in this pass"
        end
        puts "  [pending] node #{node.id} (#{node.label}): #{reason}"
      end
      puts "\nBring each one online and re-run `rake agent:datachannel_backfill` until this"
      puts "list is empty. The task is idempotent — re-running costs nothing."
    end

    # --- Exit status --------------------------------------------------------------------
    # A per-node or per-volume failure used to print [fail] and still exit 0, so an
    # automated caller (the provisioner) saw a successful seed while dispatch stayed
    # blocked. Any failure is now a non-zero exit; a scoped run additionally fails if the
    # node it was asked about did not latch, since that is the entire point of the call.
    failed_nodes = node_seen.each_value.reject { |node| node_ok[node.id] }
    unlatched_target = target && node_scope.where(datachannel_backfilled_at: nil).exists?
    if failed_nodes.any? || unlatched_target
      message = "\nagent:datachannel_backfill FAILED — #{failed_nodes.size} node(s) had failures"
      message += "; scoped node #{target.id} is not latched" if unlatched_target
      puts "#{message}."
      exit 1
    end
  end
end
