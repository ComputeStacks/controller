# v9.6 — Controller Metadata Cutover

Controller-side procedure for moving customer metadata onto the node agents.
Node-side steps (agent binary, Consul → `:8502`, firewall) are in **v96 Node Agent Cutover.md**;
do those per node first.

## 1. Deploy the controller

`NODE_ENROLLMENT_TOKEN` must be the **same** value on the controller and in the Ansible vault
(`bin/rails secret` to generate). The Step 3 / Step 6 endpoint reads `ENV["NODE_ENROLLMENT_TOKEN"]`
from **inside the running container** — a blank/missing value makes it answer **401 to every
request** (it fails closed; a blank token does not disable the gate). On a containerized controller
the token therefore has to be both in the env file *and* passed into the long-lived `portal`
container:

```bash
# same token as the Ansible vault; the env file uses bare KEY=value (no quotes)
echo 'NODE_ENROLLMENT_TOKEN=<paste token>' >> /etc/default/computestacks

# add it to the `run -d` container — the only cstacks subcommand that serves the API
sed -i '/docker run -d --name portal/a\        -e NODE_ENROLLMENT_TOKEN=$NODE_ENROLLMENT_TOKEN \\' /usr/local/bin/cstacks
grep -c NODE_ENROLLMENT_TOKEN /usr/local/bin/cstacks   # expect: 1 (re-running the sed duplicates it)

# pull v9.6.0, run migrations (adds nodes.agent_token_encrypted), restart with the new env
cstacks upgrade && cstacks run
```

> Provisioner (tracked separately — **not** done here): add `NODE_ENROLLMENT_TOKEN` to the controller
> env template (`roles/controller/templates/default-computestacks.j2`) and the `-e` flag to the `run`
> block of `roles/controller/files/cstacks.sh`, so fresh provisions don't drop it.

Confirm the controller still reaches Consul: over **https/8501** it is unaffected by the `:8502`
move. An `http/8500` controller must be repointed to `:8502` first.

## 2. Mint the per-node admin tokens

```bash
bundle exec rails runner \
  'Node.where(agent_token_encrypted: nil).find_each { |n| n.update!(agent_token: SecureRandom.urlsafe_base64(32)) }'
```

## 3. Install each node's admin-token hash on its agent

Run this **from each node** — it identifies itself by source IP (matched against
`primary_ip`/`public_ip`), so no node id or hostname is needed. It fetches the node's
admin-token *hash*, validates it, appends `metadata.admin_token_hash`, and restarts the
agent. Requires `jq`; assumes no existing `metadata:` block (true on a fresh node). **Same
one-liner as *v96 Node Agent Cutover.md* → Step 2 ("Admin token hash") — keep the two in sync.**

```bash
NODE_ENROLLMENT_TOKEN='<paste NODE_ENROLLMENT_TOKEN>'
CONTROLLER=$(awk '/^computestacks:/{f=1} f&&/host:/{v=$2; gsub(/[\047"[:space:]]/,"",v); print v; exit}' /etc/computestacks/agent.yml)
HASH=$(curl -fsS -H "Authorization: Bearer $NODE_ENROLLMENT_TOKEN" "$CONTROLLER/api/system/nodes/agent_token_hash" | jq -r '.agent_token_hash // empty') \
  && [[ "$HASH" =~ ^[0-9a-f]{64}$ ]] \
  && printf '\nmetadata:\n  admin_token_hash: "%s"\n' "$HASH" >> /etc/computestacks/agent.yml \
  && systemctl restart cs-agent \
  && echo "OK: set metadata.admin_token_hash; cs-agent restarted"
```

> Fails closed: a 401 (bad token) or non‑64‑hex response writes nothing; the plaintext Bearer
> never leaves the controller. (In Ansible: run the fetch on the node → template
> `metadata.admin_token_hash` → restart, rather than the shell append.)

## 4. Seed the agents

```bash
bundle exec rake metadata:agent_backfill
```

Provisions each project's tenant and pushes its managed blobs (metadata, ssh_keys, host keys).
Idempotent and resumable — re-run for any project skipped because its node was not ready.

## 5. Rebuild the bastion images

The controller injects `METADATA_SERVICE` = the bare root `http://metadata.internal:8500` and
`METADATA_URL` = `…/v1/managed/metadata` (the new endpoint). The **bastion** images derive paths from
`METADATA_SERVICE`, and those paths are **not** covered by the legacy `/metadata` shim, so they must be
rebuilt. Request bodies and the `Authorization: Bearer` header are unchanged — only the URLs move.

- **cs-docker-images/cs-docker-bastion** (host-key + `authorized_keys` reads):
  - `init_bastion.rb`: `GET {METADATA_SERVICE}/{HOSTNAME}?raw=true` → `GET {METADATA_SERVICE}/v1/managed/{HOSTNAME}`
  - `load_ssh_keys.rb`: `GET {METADATA_SERVICE}/ssh_keys?raw=true` → `GET {METADATA_SERVICE}/v1/managed/ssh_keys`
- **docker-images/bastion** (`/db` writes):
  - `sync_state.rb`: `PUT {METADATA_SERVICE}/db/wordpress/{plugins,users,themes}` → `PUT {METADATA_SERVICE}/v1/db/wordpress/{plugins,users,themes}`
  - `migration_complete.rb`: `PUT {METADATA_SERVICE}/db/wordpress/migration_complete` → `PUT {METADATA_SERVICE}/v1/db/wordpress/migration_complete`

**phpMyAdmin needs no change** — `init_pma.rb` reads `$METADATA_URL`, which now points at the new
endpoint for new containers; already-baked containers keep working via the `/metadata` shim (and it is
`SSO_ONLY` in prod regardless).

Old php/wordpress containers (monarx) keep reading node id via their baked `METADATA_URL` → the
`/metadata?raw=true` shim until they recycle; no recreation required.

## 6. Validate

```bash
# admin-token endpoint, run ON the node (wrong/blank token => 401)
curl -fsS -H "Authorization: Bearer $NODE_ENROLLMENT_TOKEN" \
  https://<controller>/api/system/nodes/agent_token_hash

# metadata shim (use a project's consul_auth_key as the Bearer)
curl -fsS -H "Authorization: Bearer <consul_auth_key>" \
  http://<node_primary_ip>:8500/v1/kv/projects/<token>/metadata?raw=true

# managed ssh keys
curl -fsS -H "Authorization: Bearer <consul_auth_key>" \
  http://<node_primary_ip>:8500/v1/managed/ssh_keys
```

## Rollback

Per-project rollback is a bastion rebuild back to the old image. Node/agent/Consul rollback is in
**v96 Node Agent Cutover.md**. Consul is not decommissioned in this release.

***

### Dev (single node)

```bash
set -a; source .envrc; set +a            # NODE_ENROLLMENT_TOKEN is here

# step 2: mint node tokens (on the controller)
bundle exec rails runner \
  'Node.where(agent_token_encrypted: nil).find_each { |n| n.update!(agent_token: SecureRandom.urlsafe_base64(32)) }'

# step 3: on the VM, run the Step 3 one-liner (it reads the controller URL from the
# VM's agent.yml, appends metadata.admin_token_hash, and restarts cs-agent). Paste the
# NODE_ENROLLMENT_TOKEN value (it's in .envrc here) into that one-liner on the VM.

# step 4 (on the controller)
bundle exec rake metadata:agent_backfill
```

> Dev reaches Consul over `http/8500`; after moving Consul to `:8502` the controller's
> coordination calls need `:8502` too (does not affect the metadata steps above).
