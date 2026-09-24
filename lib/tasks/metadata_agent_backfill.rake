namespace :metadata do
  desc "Phase 0a: provision every project's tenant on the node agent and push its managed blobs. Idempotent + resumable. Run AFTER the agent is bound on primary_ip:8500. Set NODE_ID=<id> or NODE=<hostname> to limit the pass to the projects in that node's region (Agent::Client resolves a project's node from its region). Exits non-zero if any project failed."
  task agent_backfill: :environment do
    # Optional single-node scope, used by the provisioner when attaching one node to a live
    # fleet. Agent::Client#resolve_node picks a project's node from its region, so scoping by
    # node means "the projects in that node's region". No scope = every project, as before.
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
      puts "Scoped to node #{target.id} (#{target.label}) — projects in region #{target.region&.name.inspect}.\n\n"
    end
    node_scope = target ? Node.where(id: target.id) : Node
    # Deployment has no region_id column — a project's region is derived from its
    # containers (Deployment#region is regions[0]), so scope through that association.
    project_scope = if target
      Deployment.joins(:regions).where(regions: {id: target.region_id}).distinct
    else
      Deployment
    end

    ok = 0
    skipped = 0
    failed = []

    # Per-node admin token: the before_save mint only fires when a Node is saved,
    # so existing nodes have none yet. Mint for any missing (idempotent) BEFORE
    # provisioning projects — otherwise Agent::Client#resolve_node raises NotReady
    # for every project and the whole backfill silently no-ops. validate:false so a
    # legacy node's unrelated validation can't abort the run.
    minted = 0
    mint_failures = 0
    node_scope.where(agent_token_encrypted: nil).find_each do |node|
      node.agent_token = SecureRandom.urlsafe_base64(32)
      node.save(validate: false)
      minted += 1
    rescue => e
      puts "[warn] node #{node.id}: could not mint agent_token (#{e.class}: #{e.message})"
      mint_failures += 1
    end
    puts "minted agent_token for #{minted} node(s)" if minted.positive?

    project_scope.find_each do |project|
      # Older projects may predate the consul_auth_key era — mint before hashing.
      if project.consul_auth_key.blank? && !project.update(consul_auth_key: SecureRandom.urlsafe_base64(32))
        failed << "#{project.id} (could not set consul_auth_key)"
        next
      end

      region = project.region
      if region.nil? || region.nodes.online.empty?
        puts "[skip] project #{project.id}: no online node (re-run later)"
        skipped += 1
        next
      end

      # Idempotent: provision is an upsert, managed PUTs are full-value replaces.
      Agent::Client.new(project, region: region).provision_tenant!
      ProjectServices::StoreMetadata.new(project).perform
      ProjectServices::MetadataSshKeys.new(project).perform
      project.sftp_containers.each do |sftp|
        SftpServices::MetadataSshHostKeys.new(sftp).perform
      end

      ok += 1
      puts "[ok] project #{project.id}"
    rescue Agent::Client::NotReady => e
      puts "[skip] project #{project.id}: #{e.message} (re-run later)"
      skipped += 1
    rescue => e
      puts "[fail] project #{project.id}: #{e.class}: #{e.message}"
      failed << project.id
    end

    puts "\nmetadata:agent_backfill done — ok=#{ok} skipped=#{skipped} failed=#{failed.size}"
    puts "failed: #{failed.join(", ")}" unless failed.empty?

    # A failed project used to print [fail] and still exit 0, so an automated caller saw a
    # successful run while that project's tenant was never provisioned on the node. Any
    # per-project failure — or a node whose agent_token could not be minted, which makes
    # every project on it fail later — is now a non-zero exit. Skips are not failures: they
    # mean "re-run once the node is online".
    if failed.any? || mint_failures.positive?
      message = "\nmetadata:agent_backfill FAILED — #{failed.size} project(s) failed"
      message += ", #{mint_failures} node(s) could not mint an agent_token" if mint_failures.positive?
      puts "#{message}."
      exit 1
    end
  end
end
