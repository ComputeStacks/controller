# v9.7 — Node Consul Retirement (per-node runbook)

v9.7.0 moves volume backup coordination, per-node firewall (NAT/ingress) rules, and the
backup/restore/export/delete job plane off Consul and onto the **cs-agent HTTP API**. The
controller has no Consul client at all in this release — Consul is *not* a runtime fallback,
and rollback is the reverse cutover.

Every node must be on the Consul-free **cs-agent v3.1.0 or newer** before the new controller
starts. (The 2026-08-02 rollout shipped **v3.1.1**.)

> Roll every node the same way, and **validate on a non-production node first.**

## Tooling prerequisite (per node, before anything else)

**`sqlite3` is not installed on the nodes by default** — it is needed for the Pass A snapshot
(the rollback anchor) and the Pass C volume/schedule verification. Install it on every node up
front, so you are not doing it mid-window with the controller down:

```bash
apt-get update && apt-get install -y sqlite3
command -v sqlite3        # -> /usr/bin/sqlite3
```

Note this is *not* the same thing as the agent's own sqlite support — the agent has it built in.
`sqlite3` here is purely the operator CLI for reading and snapshotting `control.db`.

## Ordering

Node work happens in **two passes**, with controller steps in between. The controller is
**off** during Pass B, and no node may serve a v3 agent to a v9.6.2 controller.

```
Pass A (all nodes, controller still running) → snapshot
   ↓
Stop the controller
   ↓
Pass B (all nodes) → upgrade cs-agent to v3.1.0, stop Consul
   ↓
Deploy v9.7.0 controller → cstacks upgrade → rake agent:datachannel_backfill
   ↓
Pass C (all nodes) → verify
   ↓
Decommission Consul (only once the fleet is confirmed healthy)
```

Before you start:

- Drain in-flight backup/restore jobs **and any in-flight volume clones/restores**.
- Ensure the provisioner (Ansible) is ready to stop deploying Consul.
- **No scheduled backups fire** from the moment the old agent stops until the backfill latches
  each node — the v3 agent's schedule table starts empty and is rebuilt only by the backfill's
  volume PUTs. Keep the window short, or accept the gap.

## Pass A — snapshot (before the window; Consul and the old agent still up)

### A0. Remove the stale pre-v9.6 binary (do this first, on every node)

A node upgraded from v9.0 or earlier may still carry the **tarball-era agent at
`/usr/local/bin/cs-agent`** (agent v1.5.0). The apt package installs to `/usr/bin/cs-agent`, and
`/usr/local/bin` comes *first* in root's `PATH` — so typing `cs-agent` runs the ancient binary,
which has no version flag and boots a full second agent against current production state
(legacy `expose-ports` / `container-inbound` iptables reconcile, stale Consul KV writes).

> Usually only a handful of long-lived nodes carry it. The check below is cheap and
> idempotent — keep running it, since a node rebuilt from an old image would reintroduce
> the file.

```bash
systemctl cat cs-agent | grep ExecStart          # confirm the unit uses /usr/bin/cs-agent
ls -l /usr/local/bin/cs-agent 2>/dev/null        # the landmine, if present
rm -f /usr/local/bin/cs-agent
hash -r                                          # drop the shell's cached path
command -v cs-agent                              # -> /usr/bin/cs-agent
```

Never invoke the binary by hand on a live node regardless — use `systemctl` and the journal.

### A1. Snapshot

The `control.db` snapshot is the rollback anchor **and** the state-loss boundary: any
ingress-rule, volume, or backup-config change made after it is taken is lost if you roll back
to it. Take it as late as you can.

```bash
# consistent copy even with WAL active -- do NOT plain `cp` a live sqlite db
sqlite3 /var/lib/cs-agent/control.db ".backup '/root/control.db.pre-v97'"
ls -l /root/control.db.pre-v97

cp -a /etc/computestacks/agent.yml /root/agent.yml.pre-v97
nft list ruleset > /root/nft.pre-v97

# record BOTH versions -- the apt package version and the agent's own version string are
# different numbering schemes (package 1.5.0 ships agent 2.0.0). The package version is the
# exact rollback target; the agent version is what the changelog and this runbook talk about.
dpkg-query -W -f='${Version}\n' cs-agent > /root/cs-agent.pkgversion.pre-v97
journalctl -u cs-agent -o cat | grep 'Starting CS-Agent' | tail -1 > /root/cs-agent.version.pre-v97
cat /root/cs-agent.pkgversion.pre-v97 /root/cs-agent.version.pre-v97
```

> **If a stray agent was started by hand** (see A0): `pgrep -af cs-agent` shows more than the
> systemd process. Kill the one that is not `systemctl show -p MainPID --value cs-agent` — no
> `-9`, let it close cleanly — then check the live firewall for resurrected legacy chains
> (`iptables -t nat -S | grep -c expose-ports` and `iptables -S | grep -c container-inbound`,
> both must be `0` post-v9.6), confirm `nft list table ip cs_agent` still matches
> `/root/nft.pre-v97`, and re-take the `control.db` snapshot.

## Pass B — upgrade the agent, then stop Consul (controller is OFF)

```bash
apt-get update
apt-cache policy cs-agent                    # note the candidate PACKAGE version before upgrading
apt-get install -y cs-agent

systemctl is-active cs-agent                 # -> active

# the running binary's own version -- this is the 3.1.x check. The package version is a
# different scheme and will NOT read 3.1.x.
SINCE=$(systemctl show -p ActiveEnterTimestamp --value cs-agent)
journalctl -u cs-agent -o cat --since "$SINCE" | grep -m1 'Starting CS-Agent'
# -> Starting CS-Agent: version=3.1.1 commit=... date=...   (3.1.0 or newer)

journalctl -u cs-agent -o cat --since "$SINCE" | tail -40
# expect the additive control.db migration, no errors
```

⛔ **Gate — the agent must be healthy and its firewall table intact before Consul goes away:**

```bash
nft list table ip cs_agent >/dev/null 2>&1 && echo "cs_agent OK" || echo "STOP: no cs_agent table"
```

Then stop Consul (the containerized unit from the v8/v9 runbooks):

```bash
systemctl disable --now consul
systemctl is-active consul                   # -> failed  (see note below; "inactive" is fine too)
docker ps --filter name=consul               # -> empty (the container is gone/stopped)
```

Notes for this step:

- **Expect this line once a minute until the backfill runs — it is not an error:**

  ```
  cs-agent.cs-firewall: firewall desired-state not yet populated; leaving live published-port table untouched
  ```

  The v3 agent's desired-state tables start empty. Rather than render an empty firewall (which
  would tear down every published port), it leaves the live nftables table exactly as the old
  agent left it. Published ports keep working through the whole gap. The message stops as soon as
  the controller's backfill PUTs the node's firewall rules. Seeing it repeat is confirmation the
  gap is being handled safely, not a signal to intervene.
  You will also see `Enforcing cross-project network isolation in DOCKER-USER` at boot — that is
  the one rule set that *does* re-render immediately, as called out above.
- **`is-active` reports `failed`, not `inactive`, and that is the expected result.** `consul` is a
  `docker run` unit, so stopping it kills the container and systemd sees a non-zero exit. What
  actually matters is that the process is gone and the port is closed — verify that rather than
  trusting the unit state:

  ```bash
  docker ps --filter name=consul --format '{{.Names}}\t{{.Status}}'   # -> empty
  ss -tunlp | grep -c consul                                          # -> 0
  ```

  Do **not** try to "clean up" the failed state with `systemctl reset-failed` before the
  decommission step — leaving it visible is a useful reminder that Consul is deliberately down
  and still rollback-able.
- Leave the `consul:` block in `agent.yml` alone. v3.1.0 does not use it, and keeping it makes
  rollback a single file copy.
- Do **not** `docker rm` the Consul container or delete its data directory yet — that container
  is the second rollback anchor. It goes at decommission time.
- The agent migrates `control.db` additively and leaves the live published-port nftables table
  and running workloads untouched through the gap. **One exception:** the `DOCKER-USER`
  cross-project isolation rules re-render at agent boot, so cross-project reachability of
  published ports changes here, not at backfill time.

## Controller (once every node has finished Pass B)

```bash
cstacks upgrade                              # backs up the database, runs db:migrate

# the rake task runs INSIDE the controller container -- shell in first:
cstacks container
bundle exec rake agent:datachannel_backfill
```

The backfill PUTs every online node's firewall rules and every volume's backup desired-state to
the owning node's agent, then latches `nodes.datachannel_backfilled_at` **only for nodes whose
full pass succeeded**. Until a node latches, the controller refuses to dispatch backup, restore,
export and delete tasks to it (recording a warn system event, deduplicated per node every 15
minutes). It is idempotent and resumable.

Read the output — do not just check the exit code:

- `[pending]` lines at the bottom list every node still gated out of dispatch. Nodes that are
  **disconnected or in maintenance are excluded from the pass entirely**. Bring them online and
  re-run until that list is empty.
- `grep '\[skip\] volume'` — a volume with no online node is skipped *without* blocking its node
  from latching, and its backup schedule is not seeded until the next dispatch self-heals it.

## Pass C — verify (per node, after the backfill latches)

```bash
# 1. firewall renders (family ip, not inet)
nft list table ip cs_agent

# 2. the firewall desired-state landed AND the populated sentinel latched
sqlite3 -header -column /var/lib/cs-agent/control.db "select key, value from control_meta;"
#    -> firewall_populated|1   and   volumes_populated|1
sqlite3 -header -column /var/lib/cs-agent/control.db \
  "select node, datetime(updated_at,'unixepoch') as updated from firewall_rules;"

# 3. volumes + backup schedules seeded by the backfill
sqlite3 /var/lib/cs-agent/control.db \
  'select count(*) from volumes; select count(*) from schedules;'
sqlite3 -header -column /var/lib/cs-agent/control.db \
  "select volume_name, cron_expr, datetime(next_fire_at,'unixepoch') as next_fire
   from schedules limit 10;"
```

**`control_meta.firewall_populated` is the gate**, not the `firewall_rules` row itself
(`firewall/firewall.go:30`). The agent skips the published-port render entirely until that
sentinel latches, so an unpopulated `control.db` can never be mistaken for "the controller sent
zero rules" and close every port. `store.PutFirewallRules` sets the sentinel in the same
transaction as the row upsert, so a row with a recent `updated_at` means the sentinel is set too;
`updated_at` is the moment the PUT landed, and the "not yet populated" log line stops within one
reconcile tick (60s) after it.

Two things *not* to worry about here:

- **`generation` / `applied_generation` are both `0` and stay that way.** The columns exist
  (added by a v3.1.x migration) but the writeback is not wired yet — see the comment at
  `store/control.go:140`. They are not a health signal in this release.
- **The `node` label is cosmetic.** The PUT is addressed by `primary_ip`
  (`Agent::Client#base_url`); the hostname in the path is only a label, the agent does not
  validate it, and `PutFirewallRules` deletes any row under a different label to keep exactly one
  row per node-DB. A label mismatch is not a failure mode.

An empty `schedules` on a node whose volumes are listed means the backfill's volume PUTs did not
land — re-run the rake task before anything relies on scheduled backups. This check is node-side
only; no controller page shows it. (Schema for reference: `volumes.name`, and
`schedules.volume_name / cron_expr / next_fire_at / updated_at`, timestamps stored as unix
epoch integers.)

```bash
# 3. changelog state (table names vary by build -- discover first)
sqlite3 /var/lib/cs-agent/control.db '.tables'
```

From the controller:

```bash
# the per-node changelog cursor advances (no admin page exposes it)
bundle exec rails runner 'Node.order(:id).each { |n| puts "#{n.id} #{n.label} cursor=#{n.changelog_cursor} backfilled=#{n.datachannel_backfilled_at}" }'
```

Run that twice, a minute apart, on a node with activity — the cursor should move. Then round-trip
a real task: fire a manual backup on one volume per node and watch the event log reach
`completed` (or check its `agent_tasks` row in the controller database).

**Ack, not prune.** Pruning of acked changelog entries only begins once entries pass the agent's
7-day retention floor, so it is *not* observable during the window. Confirm the ack watermark
advances now; check pruning a week later.

## Decommission Consul

Only once the fleet is confirmed healthy: remove the Consul processes on each node and the
provisioner's Consul role. Rollback is no longer available after this.

## Rollback (valid until decommission)

Per node — **restore the snapshot first**, because a v2.0.0 binary refuses to boot against a
migrated DB:

```bash
systemctl stop cs-agent
cp -a /root/control.db.pre-v97 /var/lib/cs-agent/control.db
rm -f /var/lib/cs-agent/control.db-wal /var/lib/cs-agent/control.db-shm
chown --reference=/var/lib/cs-agent /var/lib/cs-agent/control.db

# downgrade to the exact PACKAGE version recorded in Pass A -- not "2.0.0", which is the
# agent's own version string and is not a valid apt version.
apt-get install -y --allow-downgrades "cs-agent=$(cat /root/cs-agent.pkgversion.pre-v97)"

cp -a /root/agent.yml.pre-v97 /etc/computestacks/agent.yml
systemctl enable --now consul
systemctl start cs-agent
systemctl is-active cs-agent consul

SINCE=$(systemctl show -p ActiveEnterTimestamp --value cs-agent)
journalctl -u cs-agent -o cat --since "$SINCE" | grep -m1 'Starting CS-Agent'
# -> version=2.0.0 (matches /root/cs-agent.version.pre-v97)
```

**The agent downgrade is not optional.** A v3.x agent under a v9.6.2 controller still answers the
metadata API, so the fleet looks alive while the entire coordination plane is dead: backups and
restores never run and ingress changes never apply, both silently.

Controller side:

- Redeploy the previous controller (v9.6.2).
- **Do not run `db:rollback`.** The v9.7.0 migrations are additive and v9.6.2 runs correctly
  against the migrated schema. Reversing them drops `volume_clone_jobs`, whose rows are the only
  pointers to temporary clone snapshots in source borg repositories — rolling back leaks those
  archives permanently. Any clone or restore in flight at rollback is stranded and needs manual
  cleanup.
- **Re-push desired state changed during the window.** v9.7.0 writes desired state only to the
  agents, never to Consul, so restoring a `control.db` snapshot discards it while the controller
  database still believes it was applied. Re-save any ingress rules and volume backup settings
  changed during the window so v9.6.2 writes them back to Consul — otherwise a volume created in
  the window silently never gets scheduled backups again.
- **If you later retry the upgrade,** first reset the changelog cursor for every node whose
  `control.db` you restored or recreated:

  ```bash
  bundle exec rails runner 'Node.where(id: [1,2,3]).update_all(changelog_cursor: 0)'
  ```

  A restored database restarts the changelog sequence at 1, so a controller still holding the
  high cursor from the failed attempt polls above everything the agent will ever produce,
  receives an empty page indistinguishable from a healthy one, and silently never sees another
  task result, repository update, or container action. Nothing alerts, and the undelivered
  entries are pruned after 7 days.

---

### Notes

- **Two version schemes.** The apt package version and the agent's self-reported version are
  unrelated (package `1.5.0` ships agent `2.0.0`). Anywhere this runbook or the changelog says
  "v3.1.0" or "v2.0.0" it means the *agent* version, which you read from the journal's
  `Starting CS-Agent: version=…` line. Anywhere apt is involved, use the package version from
  `apt-cache policy cs-agent` / `dpkg-query -W cs-agent`. The v9.7.0 CHANGELOG rollback line
  (`apt-get install --allow-downgrades cs-agent=2.0.0`) has these confused — use the package
  version recorded in Pass A instead.
- Published-port DNAT is untouched by the agent upgrade; only `DOCKER-USER` cross-project
  isolation re-renders at boot.
- The `cs_agent` nftables table is family `ip`, not `inet`.
- Whether v3.1.0 tolerates a leftover `consul:` block in `agent.yml` is assumed here (it should
  simply be ignored). If the agent errors at boot, comment the block out and restart.
