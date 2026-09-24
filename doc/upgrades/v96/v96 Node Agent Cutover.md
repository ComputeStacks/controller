# v9.6 — Node Agent Cutover (no reboot)

v9.6 migrates the node agent (`cs-agent`) from the old Docker‑container deployment to a
**native systemd binary**, and replaces the iptables `expose-ports` / `container-inbound`
reconcile with a native **nftables `cs_agent` table**. Customer metadata now comes from the
agent's own HTTP API on `:8500`, so **Consul's HTTP listener moves to `:8502`**.

This runbook performs the full node cutover **without rebooting**. A reboot is the simpler
path — it lets `cs-recover_iptables` re‑apply a clean ruleset from scratch — but needs a
maintenance window. Instead we leave the legacy rules serving traffic, bring up the new
`cs_agent` table alongside them, confirm parity, and only then delete the old rules by hand.

> Roll every node the same way, and **validate on a non‑production node first.**

## Why the order matters

- The agent now **binds `:8500`** for the metadata API, so Consul must vacate `:8500` (move to
  `:8502`) **before** the new agent starts — otherwise the metadata server can't bind, and the
  agent's own Consul client would talk to itself.
- The legacy iptables rules and the new `cs_agent` nftables table can DNAT the same ports at the
  same time with **no harm** (same targets; conntrack picks one per flow). So the safe sequence
  is: render `cs_agent` → confirm it covers every published port → *then* remove the old rules.
- Commenting lines out of `cs-recover_iptables` only affects the **next boot**. The rules already
  applied in the kernel persist until you delete them (or reboot) — that hand‑deletion is the
  whole point of this runbook.

## Preconditions (per node — abort if any fail)

```bash
# nftables backend (Debian 12/13)
update-alternatives --query iptables | grep Value          # -> /usr/sbin/iptables-nft

# Project bridges (named net<hash>) run in nat-unprotected mode -- this is what
# makes removing container-inbound safe (Docker's per-bridge accept covers the
# forward path). NOTE: do not check docker0 / the default "bridge" or "ops" --
# only the project networks carry this option.
for n in $(docker network ls --filter driver=bridge --format '{{.Name}}' | grep '^net'); do
  printf '%-40s %s\n' "$n" \
    "$(docker network inspect "$n" --format '{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}')"
done
# expect: every line reports  nat-unprotected

# Consul is reachable on :8502 and :8500 is free
# NOTE: Consul binds the node's PRIVATE IP, not loopback -- 127.0.0.1 will be refused.
CONSUL_IP=$(hostname -I | awk '{print $1}')   # or read it from the consul container config
curl -s -o /dev/null -w '8502 -> %{http_code}\n' "http://$CONSUL_IP:8502/v1/status/leader"   # -> 200
```

> If the bridges are **not** `nat-unprotected`, rebuild the node's container networks first
> (see *v93 Docker Network Changes*) before cutting over.

## Coordinated with the controller / provisioner

These are not node‑local — confirm they're in place for the node being cut over:

- Consul's HTTP listener has moved to **`:8502`**.
- New containers receive **`CS_NODE_ID`**; existing containers keep working via the compatibility
  shim (`…/metadata?raw=true`) — **no container recreation required**.
- If the controller **writes** customer metadata: set **`NODE_ENROLLMENT_TOKEN`** on the
  controller (env + Ansible vault) so the node can fetch its own admin-token hash in Step 2.
  (The read path and the firewall cutover work without this.)

## 0. Snapshot for rollback

```bash
iptables-save                       > /root/iptables.pre-cutover
nft list ruleset                    > /root/nft.pre-cutover
cp -a /etc/computestacks/agent.yml    /root/agent.yml.pre-cutover
```

## 1. Stop and remove the old containerized agent

Live iptables rules persist, so published ports keep working through this step.

```bash
systemctl disable --now cs-agent
docker rm -f cs-agent 2>/dev/null || true
rm -f /etc/systemd/system/cs-agent.service     # the native package unit lives in /lib/systemd/system
```

## 2. Point the agent at Consul's new port

Edit `/etc/computestacks/agent.yml`:

```yaml
consul:
  host: 127.0.0.1:8502        # was 127.0.0.1:8500
```

Leave `metadata.listen_addr` at the default `:8500` (or set it to `<primary_ip>:8500`).

**Admin token hash** — only needed if the controller *writes* customer metadata (the read
path and the firewall cutover work without it). Run this **on the node**: it fetches this
node's admin-token *hash* from the controller (`GET /api/system/nodes/agent_token_hash`,
gated by `NODE_ENROLLMENT_TOKEN`; the node is matched by its source IP — the plaintext
Bearer never leaves the controller), validates it, and appends `metadata.admin_token_hash`.
Requires `jq`. Assumes no existing `metadata:` block (true on a fresh node):

```bash
ENROLLMENT_TOKEN='<paste NODE_ENROLLMENT_TOKEN>'
CONTROLLER=$(awk '/^computestacks:/{f=1} f&&/host:/{v=$2; gsub(/[\047"[:space:]]/,"",v); print v; exit}' /etc/computestacks/agent.yml)
HASH=$(curl -fsS -H "Authorization: Bearer $ENROLLMENT_TOKEN" "$CONTROLLER/api/system/nodes/agent_token_hash" | jq -r '.agent_token_hash // empty') \
  && [[ "$HASH" =~ ^[0-9a-f]{64}$ ]] \
  && printf '\nmetadata:\n  admin_token_hash: "%s"\n' "$HASH" >> /etc/computestacks/agent.yml \
  && systemctl restart cs-agent \
  && echo "OK: set metadata.admin_token_hash; cs-agent restarted"
```

> The chain fails closed: a bad enrollment token (401) or non‑64‑hex response writes nothing.
> If `agent.yml` already has a `metadata:` block (e.g. you set `listen_addr`), add
> `admin_token_hash:` under it by hand instead of running the append.

## 3. Install the native agent

```bash
apt-get install -y cs-agent          # from the apt repo;  or:  dpkg -i ./cs-agent_*.deb
# do NOT run the binary by hand -- it has no version flag and boots a second agent.
# Read the running build from the journal instead:
journalctl -u cs-agent -o cat | grep 'Starting CS-Agent' | tail -1
systemctl is-active cs-agent         # -> active
```

## 4. ⛔ Gate — `cs_agent` must render at full parity

**Do not delete anything until all three checks pass.**

```bash
# table exists?
nft list table ip cs_agent >/dev/null 2>&1 && echo "table OK" || echo "STOP: no cs_agent table"

# every published port carried over? (cs_agent splits by proto; old chain is combined)
CSA=$(( $(nft list map ip cs_agent dnat_tcp 2>/dev/null | grep -oE '[0-9]+ :' | wc -l) \
      + $(nft list map ip cs_agent dnat_udp 2>/dev/null | grep -oE '[0-9]+ :' | wc -l) ))
OLD=$(iptables -t nat -S expose-ports 2>/dev/null | grep -c -- --to-destination)
echo "cs_agent=$CSA  old=$OLD"; [ "$CSA" = "$OLD" ] && echo "PARITY_OK" || echo "STOP: mismatch"

# no render error since the agent's CURRENT start (scoped, so an error left in
# the journal by an earlier/failed run does not false-positive)
SINCE=$(systemctl show -p ActiveEnterTimestamp --value cs-agent)
journalctl -u cs-agent -o cat --since "$SINCE" | grep -q "Failed to render" \
  && echo "STOP: render error — see: journalctl -u cs-agent --since \"$SINCE\"" || echo "no render error"
```

At this point `cs_agent` and the old iptables rules are both DNAT'ing the same ports — the
expected, harmless overlap.

## 5. Trim the boot script (keeps a *future* reboot clean too)

In `/usr/local/bin/cs-recover_iptables`, comment out or remove the lines the agent has taken
over (this does **not** touch the live ruleset):

- `iptables -t nat -N expose-ports`
- `iptables -t nat -A PREROUTING -j expose-ports`
- `iptables -t nat -A OUTPUT -j expose-ports`
- `iptables -N container-inbound`
- `iptables -A FORWARD -j container-inbound`

## 6. Remove the live legacy rules (the no‑reboot step)

Only after the Step 4 gate passed. For each chain: delete the jump(s), flush, then drop it.

```bash
# nat / expose-ports  (two jumps: PREROUTING + OUTPUT)
iptables -t nat -D PREROUTING -j expose-ports
iptables -t nat -D OUTPUT     -j expose-ports
iptables -t nat -F expose-ports
iptables -t nat -X expose-ports

# filter / container-inbound
iptables -D FORWARD -j container-inbound
iptables -F container-inbound
iptables -X container-inbound
```

> **Do NOT flush conntrack.** Established connections keep the DNAT already recorded in their
> conntrack entry; only *new* connections route through `cs_agent`. There is no forwarding gap.

## 7. Verify

```bash
iptables -t nat -S | grep -c expose-ports                  # -> 0
iptables -S      | grep -c container-inbound               # -> 0
nft list table ip cs_agent >/dev/null && echo "cs_agent present"
iptables -S DOCKER-USER | head     # cross-project isolation intact (agent-managed, unchanged)
```

Then, **from outside the node**, open a *new* connection to a published port and confirm it
reaches the container (now served by `cs_agent` alone). Test one port low in the range and one
near 50000.

## Rollback (no reboot)

```bash
nft delete table ip cs_agent
iptables-restore < /root/iptables.pre-cutover        # reinstates the old chains/rules, live
cp -a /root/agent.yml.pre-cutover /etc/computestacks/agent.yml
# then reinstate the old containerized cs-agent unit + image, and repoint Consul HTTP to :8500
systemctl restart cs-agent
```

---

### Notes

- `DOCKER-USER` cross‑project isolation is unchanged and remains agent‑managed; there is nothing
  to delete there.
