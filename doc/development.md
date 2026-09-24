# Development environment

This is the only doc you need to bring up a working ComputeStacks dev environment
from scratch. If something here disagrees with the installer scripts, the scripts
win — this file is meant to track them, not the other way around.

## What this is

Two machines, node-only:

- **A container node VM** — a fresh Ubuntu 26.04 ("resolute") amd64 machine,
  bootstrapped by `lib/dev/single-node.sh`. It runs Docker, cs-agent, haproxy, the
  container registry filesystem, and (collapsed onto this one host, unlike
  production) cadvisor/prometheus/loki/fluentd. It runs no database and no
  nameserver.
- **Your workstation** — Ubuntu 26.04 — bootstrapped by
  `lib/dev/workstation.sh`, then holding your clone of this repository. It runs
  Rails directly (`./bin/dev` serves `:3005`) plus postgres, redis, PowerDNS and
  pebble (an ACME test server) from `docker-compose.yml`.

**`workstation.sh` runs *before* the repository is cloned**, on a bare VM, and does
not touch a checkout. Cloning is a separate, manual step you do afterward, with
your own credentials — see [Bring-up](#bring-up-in-order).

**No TLS anywhere except the container registry**, where the registry image
structurally requires a certificate. This is deliberate, not a gap — see
[DNS and TLS](#dns-and-tls-what-resolves-and-what-doesnt) below.

## Source of truth

The ComputeStacks Ansible provisioner — the tooling that builds real production
nodes — is authoritative for how a node is actually built. It is a separate,
non-public repository. `lib/dev/single-node.sh` is a hand-maintained, stripped
single-host derivative of it and **will drift**; its header comment carries a
section → provisioner-role map and a "last synced" date. If you don't have access
to the provisioner, treat `single-node.sh` as the reference and expect it to lag
production.

## Scope of the two scripts

Quoting the design decision behind this rebuild:

> For the workstation part... the scope should be just getting the VM mostly
> configured — all the developer tools installed (docker, mise, etc),
> communication working between the test node and the workstation VM, and the
> user account setup.
>
> For the node, because you're not actually installing ComputeStacks you won't be
> able to test it fully end to end, but you should be able to test all the
> individual components that they installed correctly and will accept the
> provisioning from ComputeStacks at a later date.

Concretely:

- **`workstation.sh`** installs Docker, the compose plugin, git, tmux, `just`,
  mise, and the `pg`/ruby-build build dependencies; generates an SSH keypair;
  writes a file of generated secrets. It does **not** run `mise install` (there is
  no `.tool-versions` yet — that comes from the clone) and it does **not** clone
  anything.
- **`single-node.sh`** installs and self-checks every individual component a real
  node needs (Docker, kernel modules, haproxy, the wildcard/registry
  certificates, node_exporter, cadvisor/prometheus/loki, cs-agent) and proves each
  one is healthy on its own. It cannot prove an end-to-end deployment, because
  nothing here installs a real ComputeStacks controller against production data —
  that proof only comes from actually running this repository against the node,
  which is exactly what the rest of this doc walks through.

## DNS and TLS: what resolves and what doesn't

This was an open question; it is now settled as a deliberate boundary, not a bug.

- The **node** resolves `controller.cstacks.local`, `registry.cstacks.local` and
  `a.cstacks.local` from a managed block in its own `/etc/hosts`, written by
  `single-node.sh`. This side works with no action from you.
- The **workstation** has no such resolution. The `cstacks.local` zone baked into
  the dev PowerDNS image (`lib/dev/powerdns/Dockerfile`, built by `docker compose
  up -d`) points every one of those records at `127.0.0.1`. That was correct for
  the old all-in-one Vagrant box, where the node *was* `127.0.0.1`. It is wrong
  for this two-machine split: from the workstation, `registry.cstacks.local` and
  `a.cstacks.local` do not resolve to the node.
- **What this costs:**
  - The controller resolves `Setting.registry_base_url`
    (`registry.cstacks.local`) itself when it talks to the container registry
    (`app/models/container_registry.rb`), so registry push/pull operations
    initiated from the controller need that name to reach the node.
  - Reaching a deployed test container in a browser needs `*.a.cstacks.local` to
    resolve to the node.
- **The stance:** left to you, deliberately. Every developer's setup differs —
  some run a reverse proxy in their homelab, some add host entries, some run a
  local resolver. Cheap options, neither prescribed nor wired up for you:
  - Add `registry.cstacks.local` and `a.cstacks.local` (plus any specific
    `*.a.cstacks.local` test hostnames you use) to the workstation's own
    `/etc/hosts`, pointed at the node's IP.
  - If you need the wildcard (`*.a.cstacks.local`) to resolve generally, point a
    per-domain resolver at the node's IP for that zone instead of at the dev
    PowerDNS container.
  - **No TLS is set up anywhere except the container registry.** Don't add any —
    a single-node dev environment is never internet-exposed and sits on one L2.

## Prerequisites

- **Node VM:** a fresh Ubuntu 26.04 ("resolute") amd64 machine, reachable from the
  workstation, that you can run commands on as root (SSH, or a console).
- **Workstation:** Ubuntu 26.04, with a regular sudo-capable user
  account.
- A checkout of this repository somewhere you can copy files from (your laptop, a
  colleague's machine — anywhere), to get the two scripts onto the two VMs. The
  public mirror can lag this branch, so don't fetch the scripts by URL; copy the
  files themselves.

## Bring-up, in order

The ordering constraint: enrolling the node needs the controller to already
hold a `Node` row, and that row is created by `rake setup_dev`, which needs the
app running against a database — so the node is installed once *before* the
controller exists (trusting the workstation's key as it does), and enrolled in
a second, short pass afterward. And the workstation's key has to exist before
the node install, since that install is what trusts it — so **`workstation.sh`
runs first**, on the workstation, before anything touches the node.
`single-node.sh` deliberately prints a `NOT ENROLLED` banner and exits 0 on its
first (pre-enrollment) run. That's expected, not a failure.

### 1. Bootstrap the workstation

From your checkout, copy the installer to the workstation VM and run it there
as root:

```bash
scp lib/dev/workstation.sh <you>@<workstation-vm-ip>:
ssh <you>@<workstation-vm-ip>
sudo bash workstation.sh --user "$(whoami)" --node-ip <node-vm-ip>
```

This installs Docker (and adds you to the `docker` group — **log out and back
in, or run `newgrp docker`**, before step 4 below), the ruby-build/`pg` build
dependencies, git, tmux, `just`, and mise (with the shell activation line added
to your `.bashrc`/`.zshrc`). It does **not** run `mise install` —
`.tool-versions` doesn't exist until you clone. It generates an SSH keypair at
`~/.ssh/computestacks_dev` (not inside any repo, so it survives a re-clone) and
writes `~/computestacks-dev.env` (mode 0600) containing a generated
`SECRET_KEY_BASE`, `USER_AUTH_SECRET`, `NODE_ENROLLMENT_TOKEN`, `DEV_VM_IP`, a
commented `CONTROLLER_IP`, `PORTAL_HTTP_SCHEME=http` and `CS_SSH_KEY`. It prints
all of this at the end too (along with the public key you need next), but the
file is there so you don't have to scroll back. **Re-running never regenerates
these values** — regenerating `SECRET_KEY_BASE` later would invalidate every
already-encrypted node `agent_token`.

Keep this terminal (or `~/computestacks-dev.env`) handy — the next step needs
both the public key and `NODE_ENROLLMENT_TOKEN` from it.

### 2. Install the node VM

From your checkout, copy the installer and the workstation's new public key to
the node VM and run it there as root:

```bash
scp lib/dev/single-node.sh ~/.ssh/computestacks_dev.pub root@<node-vm-ip>:/root/

ssh root@<node-vm-ip> "bash single-node.sh \
  --controller-ip <this-workstation-ip> \
  --vm-ip <node-vm-ip> \
  --ssh-pubkey-file /root/computestacks_dev.pub \
  --token '<NODE_ENROLLMENT_TOKEN from ~/computestacks-dev.env>'"
```

Two things bite here, both because `ssh` hands the remote end **one string**
that the remote shell then re-splits:

- Use `--ssh-pubkey-file` against a copied file, not `--ssh-pubkey "$(cat …)"`
  composed remotely — the key's three space-separated fields would arrive as
  three arguments and the script exits with `unknown argument: AAAAC3Nza...`.
- `--token` is **required** whenever you run this over `ssh`: ssh does not
  forward environment variables, so an exported `NODE_ENROLLMENT_TOKEN` on your
  side never reaches the remote shell.

Defaults: `--hostname csdev`, `--region dev` — both must match what `rake
setup_dev` creates later, so don't change them unless you also change the rake
task. Full flag reference: `single-node.sh --help`.

This runs steps 1–15 (Docker, kernel tuning, haproxy, the wildcard cert, the
registry filesystem, node_exporter, observability, the firewall shape, cs-agent
itself), trusts the workstation's key (step 7 — the controller can now manage
volumes, deploy LB certificates, and `rake setup_dev` can pull a certificate
over SSH), and then attempts step 16, enrollment — which cannot succeed yet,
because the controller has no `Node` row for this host. You'll see:

```
NOT ENROLLED. agent.yml has NOT been written and cs-agent will not start...
```

**This is the expected first-run result and the script exits 0.** Continue.

### 3. Clone and configure

This is deliberately manual: it needs your own credentials.

```bash
git clone https://github.com/ComputeStacks/controller.git
cd controller
```

(A team member with access to an internal remote may clone that instead.)

```bash
cp envrc.sample .envrc
```

Merge in the generated values from `~/computestacks-dev.env` (`SECRET_KEY_BASE`,
`USER_AUTH_SECRET`, `NODE_ENROLLMENT_TOKEN`, `DEV_VM_IP`, `CS_SSH_KEY`,
`PORTAL_HTTP_SCHEME`), then set:

```bash
export CONTROLLER_IP=<only if autodetection below picks the wrong interface>
```

`CONTROLLER_IP` is normally left unset: `rake setup_dev` asks the kernel which
local address it would use to route to `DEV_VM_IP` and uses that.

**`SECRET_KEY_BASE` must be at least 128 characters.** `Secret#crypt_key` raises
below that length, and node `agent_token`s are encrypted with it — so a short
value doesn't error loudly, it silently nils every token and every
`Agent::Client` call then fails in a way that looks like a networking problem.
`workstation.sh`'s generated value is already 128 hex characters; if you ever
regenerate it by hand, use `./bin/rails secret`.

`PORTAL_HTTP_SCHEME=http` is already set by `workstation.sh` and in
`envrc.sample`. Production defaults to `https`; the dev Procfile only serves
plain HTTP on `:3005`, so without this, `update_balancer_service.rb` curls a
scheme the dev app never speaks and **haproxy in dev can never receive a
config**. Leave it set.

```bash
cp config/database.sample.yml config/database.yml
```

The sample is URL-based and reads `DEV_DB_URL`/`TEST_DB_URL` from `.envrc` — no
editing needed.

```bash
mise trust && mise install
```

`.mise.toml` is tracked in git, so a fresh clone's copy is **untrusted** — mise
refuses to read a config file it hasn't been told to trust, and the trust store
is per-user, so this step is required even though `workstation.sh` already ran
as root. `.envrc` is loaded by **mise**, not direnv — `.mise.toml`'s `[env]
_.file = '.envrc'` does it. direnv is not installed and is not used anywhere in
this repo.

### 4. Bring up the workstation containers

```bash
docker compose up -d      # postgres, redis, powerdns, acme_test, guacamole
bundle install
./bin/rails db:setup
```

`workstation.sh` deliberately does not run `bundle install` — it installs the
toolchain and the headers the native extensions need (`libpq-dev` and friends)
and leaves the gems to you.

### 5. Create the Node row

```bash
bundle exec rake setup_dev
```

Creates the default location/region/network, the `LoadBalancer` and `Node` rows
(`hostname: csdev`, matching the installer's default), pulls the wildcard cert
off the node over SSH (using the SSH trust step 2 established), and sets
`Setting.hostname` etc. for the dev domains.

### 6. Enroll the node

```bash
ssh root@<node-vm-ip> "bash single-node.sh --enroll-only \
  --controller-ip <this-workstation-ip> --vm-ip <node-vm-ip> \
  --token '<the same NODE_ENROLLMENT_TOKEN>'"
```

`--token` is required here for the same reason as step 2, and this is the step
that actually consumes it: leave it off and enrollment does nothing, prints the
`NOT ENROLLED` banner again, and exits 1.

This fetches the node's admin token hash from the controller (`GET
/api/system/nodes/agent_token_hash`, now succeeding because the `Node` row from
step 5 exists), renders `agent.yml`, and (re)starts cs-agent. The self-checks
at the end now report `cs-agent is active` and a 401 from its HTTP port instead
of skipping.

### 7. Run it

```bash
./bin/dev      # overmind -> Procfile: web (:3005), worker_dev, clock
```

Log in at `http://localhost:3005` (or the workstation's address, from the node's
side).

## Verification

- `single-node.sh`'s own step 17 self-checks run at the end of both the first
  pass and `--enroll-only`, and are the fastest way to tell what's actually
  working: `docker`/`prometheus-node-exporter`/`fluentd` active, `haproxy`
  enabled (not started — see below), `cadvisor`/`prometheus`/`loki` active with
  the placement labels answering (unless `--skip-observability`), and
  post-enrollment, `cs-agent` active with a 401 on its HTTP port and the three
  `DOCKER-USER` rules present and in order.
- These checks prove every individual node component installed correctly and
  will accept provisioning — they do **not** prove an end-to-end deployment
  (creating a real container, attaching it to a load balancer, etc.). That proof
  only comes from actually using the running controller against this node.
- `curl -o /dev/null -w '%{http_code}\n' http://<node-vm-ip>:8500/v1/admin/changelog?since=0&limit=1`
  → **401 is success**: cs-agent is up and demanding auth. `curl .../` (the bare
  root) is not a useful probe — cs-agent has no route there and always answers
  404, auth or no auth.

## Troubleshooting

**`NOT ENROLLED` on the first `single-node.sh` run (step 2).** Expected —
the controller has no `Node` row yet, so enrollment can't succeed even though
the rest of the install (including trusting the workstation's key) does. Exits
0 on purpose. Run `rake setup_dev` (step 5), then re-run with `--enroll-only`
(step 6).

**haproxy is enabled but not running, and that's correct.** The distro's stock
haproxy config has no listener. The controller starts it (and gives it a real
config) only after it has something to push. `systemctl status haproxy` showing
"inactive (dead)" right after install is not a bug.

**`curl http://<node-vm-ip>:8500/` (bare root) returns 404.** Expected — cs-agent
has no route at `/`. Probe `/v1/admin/changelog?since=0&limit=1` instead, where a
401 means success.

**A rebuilt node looks healthy but never completes any task.** cs-agent's
changelog sequence number (`seq`) restarts at 1 whenever its `control.db` is
fresh (e.g. after rebuilding the VM). If the controller's stored changelog
cursor for that node is already higher than anything the new agent will ever
emit, the controller polls above every event the agent produces and sees
nothing — forever, with no alert. The node looks green; tasks never complete.

**401 fetching the agent token hash during enrollment.** Means either a wrong
`--token`/`NODE_ENROLLMENT_TOKEN`, *or* a blank `NODE_ENROLLMENT_TOKEN` on the
controller — the two are indistinguishable from the node's side. Check `.envrc`
on the workstation and restart `./bin/dev` after any change to it (Rails only
reads `.envrc` at process start).

**404 fetching the agent token hash.** The controller identifies the node by
*source IP* against the `Node` row's `primary_ip`/`public_ip` — there's no `:id`
in the route (`GET /api/system/nodes/agent_token_hash`). A 404 means the address
the controller saw doesn't match any Node row; the script prints that source
address in its warning.

**Docker group membership "not working" right after `workstation.sh`.** It
doesn't take effect in your current shell — log out and back in, or run `newgrp
docker`.

**`bundle install` fails building the `pg` gem, or `mise install` fails building
Ruby.** Means you skipped `workstation.sh` (it installs `libpq-dev` and the rest
of ruby-build's prerequisites first). Run it, or install
`build-essential autoconf patch pkg-config libpq-dev libssl-dev libyaml-dev
libreadline-dev zlib1g-dev libgmp-dev libncurses-dev libffi-dev libgdbm-dev
uuid-dev` by hand.

**`mise install` (or any `mise` command) fails with "Config files ... are not
trusted".** `.mise.toml` is tracked in git, so a fresh clone's copy is
untrusted by design. Run `mise trust` in the repo root first. The trust store is
per-user — trusting it as root (e.g. while `workstation.sh` ran) does not cover
your own account.

**`registry.cstacks.local` or `a.cstacks.local` don't resolve from the
workstation.** Expected — see [DNS and TLS](#dns-and-tls-what-resolves-and-what-doesnt).
This is a deliberate boundary, not a bug; add host entries or a resolver
yourself if you need it.

## Follow-up: `rake bootstrap:apply`

`rake setup_dev` is the current bring-up path and this doc describes it, but
it's expected to eventually be replaced by `rake bootstrap:apply` against a
checked-in dev manifest (see `doc/bootstrap_manifest.md`). That's what the
production provisioner already uses, and it encodes the node contract
correctly — including the `active: true` trap
`setup_dev.rake` has to handle by hand. This is a deliberate, larger,
separately-scoped follow-up (not started); the point of recording it here is so
the next person doesn't have to re-derive the argument for making the switch.
