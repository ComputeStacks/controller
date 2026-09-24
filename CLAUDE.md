# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ComputeStacks Controller — a Rails 7.2 / Ruby 3.4 orchestration server that provisions and manages Docker containers across remote nodes, with billing, DNS, TLS (Let's Encrypt / ACME), load balancers, and a public OAuth API. App listens on `:3005` in dev.

## Common commands

Local bring-up (one-time; full walkthrough, including the node-enrollment loop, in
`doc/development.md`):
```
# 1. On a bare workstation VM, as root -- installs docker, mise, build deps;
#    generates an SSH keypair (~/.ssh/computestacks_dev) and
#    ~/computestacks-dev.env (SECRET_KEY_BASE, USER_AUTH_SECRET,
#    NODE_ENROLLMENT_TOKEN, ...). Does NOT clone anything.
sudo bash lib/dev/workstation.sh --user "$(whoami)" --node-ip <node-vm-ip>

# 2. Copy the installer + the workstation's new public key to a SEPARATE
#    Ubuntu 26.04 "resolute" VM (the container node, nothing else) and run it
#    THERE as root. --token is required: ssh does not forward
#    NODE_ENROLLMENT_TOKEN. Trusts the workstation's key; enrollment itself
#    can't succeed yet (no Node row) -- first run ends "NOT ENROLLED", exit 0.
scp lib/dev/single-node.sh ~/.ssh/computestacks_dev.pub root@<node-vm-ip>:/root/
ssh root@<node-vm-ip> "bash single-node.sh --controller-ip <workstation-ip> \
  --vm-ip <node-vm-ip> --ssh-pubkey-file /root/computestacks_dev.pub \
  --token '<NODE_ENROLLMENT_TOKEN from ~/computestacks-dev.env>'"

# 3. Back on the workstation: clone, then merge ~/computestacks-dev.env into .envrc.
git clone https://github.com/ComputeStacks/controller.git && cd controller
cp envrc.sample .envrc   # merge in the generated values
cp config/database.sample.yml config/database.yml
mise trust && mise install   # .mise.toml is tracked -> untrusted until you say so
docker compose up -d         # postgres, redis, powerdns, pebble, guacamole
bundle install
./bin/rails db:setup
bundle exec rake setup_dev   # creates the Node row this node enrolls against

# 4. Enroll the node.
ssh root@<node-vm-ip> "bash single-node.sh --enroll-only --controller-ip <workstation-ip> \
  --vm-ip <node-vm-ip> --token '<the same NODE_ENROLLMENT_TOKEN>'"
```
`.envrc` is loaded by **mise** (`.mise.toml`'s `_.file = '.envrc'`), not direnv.
There is no `Vagrantfile` — the node is a separate VM bootstrapped by
`lib/dev/single-node.sh`, run on that VM as root, not here. No TLS anywhere
except the container registry, and the workstation cannot resolve
`registry.cstacks.local`/`a.cstacks.local` on its own — both deliberate; see
`doc/development.md`.

Day-to-day:
- Run all processes: `./bin/dev` (overmind → `Procfile`: web, worker_dev, clock)
- Build production image locally: `just build` (spins up ephemeral pg+redis, then `docker build`)

### Gemfile quirk

The real gem manifest is `Gemfile.common`, and it is the only one tracked in git. A root `Gemfile` is optional and gitignored: when an engine is mounted it `eval_gemfile`s `Gemfile.common` and adds that engine as a path gem. `.envrc` exports `BUNDLE_GEMFILE=Gemfile.common` so dev work bypasses any engine. The Dockerfile renames `Gemfile.common` → `Gemfile` when no Gemfile is present. If `bundle` behaves oddly, check which Gemfile is active.

## Architecture

**Layered request/job flow:** Controller → Service object → Sidekiq worker → Model. Each domain (containers, deployments, networks, volumes, billing, DNS, load balancers, lets_encrypt, marketplace, orders, regions, nodes, etc.) follows the same shape, with parallel namespaces under `app/services/`, `app/workers/`, and `app/controllers/` (plus `app/controllers/api/`).

When adding behavior to an existing domain, look first for the matching `*_services` / `*_workers` modules — most controller actions are thin and dispatch into one of them.

**Modular models with a sidecar directory.** Many top-level models have a same-named directory holding submodels and concerns scoped to that domain; cross-cutting model logic lives in `app/models/concerns/<domain>/`. Put new domain-scoped model code there rather than flat in `app/models/`.

**Background work.** Production runs *four* separate Sidekiq processes (see `lib/build/supervisord.conf`): `worker_system`, `worker_deployments`, `worker_acme`, plus the web app and `clockwork`. Each reads its own `config/sidekiq/*.yml.erb`. Dev collapses them into one (`config/sidekiq/dev.yml`). **Pick the queue that matches the worker's namespace** — putting deployment work on the system queue (or vice versa) means it won't run in production.

**Scheduled jobs.** `lib/clock.rb` (Clockwork) is the single source of truth for cron-like work — heartbeats, stats, billing phases, LE cert provisioning, cleanup. Add new schedules here, not in worker files.

**External integrations.** Heavy use of forked ComputeStacks gems pinned by SHA in `Gemfile.common` (`docker-api`, `docker_ssh`, `docker_registry`, `docker_volume_local/nfs`, `pdns`, `autodns`, `whmcs`). These talk to remote docker daemons over SSH/TCP, PowerDNS, and a billing system. The node agent (cs-agent v3.0.0) is reached over HTTP via `Agent::Client` (per-node admin Bearer on `Node#agent_token`): the controller PUSHes desired-state (firewall rules, volumes, tasks) to `/v1/admin/*` DOWN endpoints and PULLs node-reported truth from the per-node changelog (`Agent::ChangelogProjector` → `agent_tasks`/`agent_repositories`/`container_action_requests`; `Agent::TaskReconciler` drives EventLogs). Consul/Diplomat was retired in the v3 cutover.

**Plugins via Rails Engines.** An engine is vendored under `engines/<name>` and mounted optionally via `config/routes/engines.rb` (sample at `config/routes/engines.rb.sample`). Each engine carries its own `Gemfile`, tests, and `bin/`. Register one by editing `config/routes/engines.rb` (gitignored). See `doc/engines.md`.

## Conventions worth knowing

- Time zone is UTC application-wide (`config/application.rb`). Convert at the view layer.
- New models that have to interact with provisioning typically need: a service object (orchestrates the request), a worker (defers the actual remote call), and an event log entry — see existing domains for the pattern rather than wiring it ad hoc.
- `app/models/concerns/auditable.rb` and the `Audit` model record changes; many models include it.
- There is no webpack/vite (assets are Sprockets + importmap). Views are Slim.
- `CHANGELOG.md` is curated by hand — operator-facing prose, one bullet per change, tagged `[FIX]` / `[FEATURE]` / `[CHANGE]` / `[DEPRECATED]`. `rake generate_changelog` renders it to the `CHANGELOG.html` that ships in the container and is served at `/admin/changelog` (gitignored, so run that task once before previewing locally). It is rendered by **Redcarpet, not CommonMark**: a continuation paragraph inside an entry needs a **4-space** indent, and a nested sub-list silently truncates the entry. `rake version:check` (which `generate_changelog` invokes) keeps `VERSION` and the newest `## vX.Y.Z` heading in agreement, and additionally checks the release tag variables in a `.gitlab-ci.yml` when one is present in the context. **See `doc/changelog.md` before editing it.**
- Production releases are cut by setting `VERSION` (matching the newest `CHANGELOG.md` heading) and pushing; CI builds the image and moves the `:MAJOR`, `:MINOR` and `:latest` tags alongside an immutable per-build tag.
