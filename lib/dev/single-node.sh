#!/usr/bin/env bash
#
# ComputeStacks single-node DEVELOPMENT environment installer.
#
# Target: a fresh Ubuntu 26.04 "resolute" amd64 VM, run as root.
# Topology: node-only. This VM is the container node. Rails runs on the
# developer's workstation at :3005, and postgres / redis / powerdns / pebble /
# guacamole come from the repository's docker-compose.yml. Nothing in this
# script installs a database or a nameserver.
#
# ---------------------------------------------------------------------------
# SOURCE OF TRUTH
# ---------------------------------------------------------------------------
# The ComputeStacks Ansible provisioner (the tooling that builds real
# production nodes) is AUTHORITATIVE for everything below. This script is a
# stripped, single-host derivative of it, hand-maintained, and it WILL drift.
# When the two disagree, the provisioner is right.
#
# The provisioner is a separate repository and is not public; if you do not
# have it, treat this script as the reference and expect it to lag production.
#
# Section -> provisioner role map (mirrors playbooks/site.yml's role order,
# whose comment calls that order "a frozen contract"):
#
#   step_01_base_system ............ roles/common (packages, conflicting pkgs)
#   step_02_reboot_gate ............ roles/common/tasks/reboot_if_required.yml
#   step_03_kernel ................. roles/node_kernel  (subset -- see below)
#   step_04_docker_engine .......... geerlingguy.docker + site.yml hold/unhold
#   step_05_docker_daemon_json ..... roles/docker_config
#   step_06_docker_listener ........ roles/docker_tls   (WITHOUT the TLS half)
#   step_07_ssh_trust .............. roles/ssh_trust
#   step_08_haproxy ................ roles/haproxy
#   step_09_wildcard_cert .......... (dev only -- v1's Vagrant box did this)
#   step_10_registry ............... roles/registry + roles/acme_web's output
#   step_11_node_exporter .......... roles/node_exporter
#   step_12_preload_images ......... roles/node_observability/tasks/preload_images.yml
#   step_13_observability .......... roles/node_observability + roles/metrics
#                                    + roles/loki (collapsed onto one host)
#   step_14_firewall ............... roles/firewall  (Option A -- see below)
#   step_15_cs_agent ............... roles/cs_agent/tasks/install.yml
#   step_16_enrollment ............. roles/cs_agent/tasks/{read_token_hash,enroll}.yml
#   step_17_self_checks ............ roles/validate
#
# LAST SYNCED WITH THE PROVISIONER: 2026-09-12
#
# ---------------------------------------------------------------------------
# DELIBERATE DIVERGENCES FROM PRODUCTION (all approved, all dev-only)
# ---------------------------------------------------------------------------
#  * No TLS anywhere except the container registry, where it is structurally
#    unavoidable (the registry image requires a certificate). A single-node dev
#    environment is never internet-exposed and sits on one L2. Docker's TCP
#    socket is plain tcp://<vm ip>:2376; cs-agent, prometheus and loki are
#    plain HTTP. Production uses vault-issued mTLS for docker and an nginx TLS
#    terminator in front of prometheus/loki -- none of that exists here.
#  * No host firewall table ("Option A"). nftables is installed for tooling
#    only. No cs_static table is shipped, the INPUT policy is left at accept,
#    the ruleset is never flushed, no forward-hook chain is created, and the
#    legacy expose-ports / container-inbound chains are never re-created.
#    cs-agent still renders its own cs_agent DNAT table and the three
#    DOCKER-USER isolation rules, which are the parts that make published-port
#    and cross-project behaviour match production.
#  * No postgres and no PowerDNS on the node. The workstation's compose file
#    provides both.
#  * prometheus and loki run on this node (production puts them on a separate
#    metrics host) and on the HOST network rather than the `ops` bridge, so no
#    `ops` network is created. The controller's MetricClient / LogClient dial
#    them directly on the VM IP; there is no nginx vhost and no basic auth.
#  * alertmanager and every alerts_*.yml rule file are dropped.
#  * Backups are disabled (backups.enabled: false) -- there is no backup
#    server. `backups.key` is still generated and written so that turning them
#    on later is not a new decision.
#  * node_kernel's production-scale tuning is NOT ported. Only the module
#    loads, the inotify limits, vm.max_map_count and BBR are kept. In
#    particular vm.min_free_kbytes=524288 is actively harmful on a 6 GB VM and
#    nf_conntrack hashsize=250000 is pointless here.
#  * No blanket `apt-get upgrade`, no unattended-upgrades, no sshd hardening.
#
# ---------------------------------------------------------------------------
# THINGS THAT ARE LOAD-BEARING AND MUST NOT BE "CLEANED UP"
# ---------------------------------------------------------------------------
#  * The containers MUST be named exactly `cadvisor` and `fluentd`. The
#    controller's prometheus alert rules carry an ignore-list matched on these
#    names.
#  * The prometheus labels region=<region> node=<hostname> are a frozen
#    contract: app/models/concerns/nodes/node_metrics.rb#metric_selector
#    matches node="<hostname>",region="<region>",job=~"node-exporter" exactly.
#    Get them wrong and every order is rejected while every dashboard is green.
#  * The wildcard certificate must be at /home/cstacks/.ssl_wildcard/sharedcert.pem
#    -- lib/tasks/setup_dev.rake reads that exact path over SSH.
#  * /etc/haproxy/dhparam.pem must exist. The controller's generated haproxy
#    config carries `ssl-dh-param-file /etc/haproxy/dhparam.pem`
#    unconditionally and haproxy refuses to start without it.
#  * haproxy is ENABLED, never STARTED. The distro's stock config has no
#    listener; the controller starts it when it pushes the real config.
#  * The DOCKER-USER isolation rules are NOT written here. cs-agent >= 3.1.0
#    asserts all three itself on every reconcile, before its populated-sentinel
#    gate, so they are re-rendered at agent boot even with an empty control.db.
#    This script's only job is to make sure xt_physdev is loaded.
#  * agent.yml follows cs-agent's config/config.go, not the upstream
#    agent.sample.yml (which is wrong in ways that fail silently).
#
set -euo pipefail

# ===========================================================================
# PINNED_VERSIONS -- mirrors playbooks/group_vars/all/versions.yml.
# ===========================================================================
# Every externally-sourced version lives here, in one place. Bump deliberately
# and re-check against the provisioner; nothing below floats.
#
# apt packages -- VERIFIED 2026-09-12 against the live indexes:
#   https://download.docker.com/linux/ubuntu/dists/resolute/stable/binary-amd64/Packages
#   https://repo.computestacks.com/public/dists/stable/main/binary-amd64/Packages
# The provisioner pins docker-ce 5:29.7.2 / containerd.io 2.3.4 / buildx 0.36.1
# (checked 2026-08-28); the versions below are the newest that resolve today,
# and 29.8.0 is what actually installed on the dev VM on 2026-09-12.
readonly DOCKER_CE_VERSION="5:29.8.0-1~ubuntu.26.04~resolute"
readonly CONTAINERD_VERSION="2.3.5-1~ubuntu.26.04~resolute"
readonly BUILDX_VERSION="0.37.1-1~ubuntu.26.04~resolute"
# cs-agent 3.3.0, NOT 3.0.0. The third DOCKER-USER isolation rule landed in
# v3.1.0; a 3.0.0 agent silently reinstates cross-project reachability.
# Package version == agent version since the node-agent rename.
readonly CS_AGENT_VERSION="3.3.0"
# Ubuntu 26.04 universe. Best effort: if this exact version has rolled out of
# the archive the install falls back to whatever resolute currently ships.
readonly NODE_EXPORTER_APT_VERSION="1.10.2-1"

# Container images -- all pinned, no :latest anywhere.
readonly PROMETHEUS_IMAGE="prom/prometheus:v3.13.2"
# loki and the fluentd loki output plugin move TOGETHER or not at all: a
# plugin built against a different loki than the one receiving is a silent
# ingest failure.
readonly LOKI_IMAGE="grafana/loki:2.9.10"
readonly FLUENTD_LOKI_IMAGE="grafana/fluent-plugin-loki:2.9.10"
readonly CADVISOR_IMAGE="ghcr.io/google/cadvisor:v0.60.5"
# Images the controller expects to already be on a node when it schedules work.
readonly BORG_IMAGE="ghcr.io/computestacks/cs-docker-borg:1.6"
readonly BASTION_IMAGE="ghcr.io/computestacks/cs-docker-bastion:v2"
readonly XTRABACKUP24_IMAGE="ghcr.io/computestacks/cs-docker-xtrabackup:2.4"
readonly XTRABACKUP80_IMAGE="ghcr.io/computestacks/cs-docker-xtrabackup:8.0"

# ===========================================================================
# Ports -- playbooks/group_vars/all/ports.yml. Frozen contract.
# ===========================================================================
readonly PORT_AGENT=8500          # controller -> cs-agent; containers -> metadata.internal
readonly PORT_DOCKER=2376         # controller -> dockerd (plain TCP in dev)
readonly PORT_PROMETHEUS=9090     # MetricClient (setup_dev hard-wires this)
readonly PORT_LOKI=3100           # LogClient (setup_dev hard-wires this)
readonly PORT_FLUENTD=9432        # docker log driver -> fluentd, loopback only
readonly PORT_NODE_EXPORTER=9100
readonly PORT_CADVISOR=8080
readonly PORT_HAPROXY_STATS=81    # must equal load_balancer.stats_bind
# Non-production container registries are allocated ports from 45000 upwards
# (app/models/container_registry.rb#set_port!).
readonly REGISTRY_PORT_BEGIN=45000
readonly REGISTRY_TRUST_PORT_COUNT=10

# ===========================================================================
# Names and paths -- must match lib/tasks/setup_dev.rake.
# ===========================================================================
readonly LB_DOMAIN="a.cstacks.local"
readonly REGISTRY_DOMAIN="registry.cstacks.local"
readonly CONTROLLER_DOMAIN="controller.cstacks.local"
readonly CSTACKS_USER="cstacks"
readonly CSTACKS_HOME="/home/cstacks"
readonly WILDCARD_DIR="${CSTACKS_HOME}/.ssl_wildcard"
readonly WILDCARD_PEM="${WILDCARD_DIR}/sharedcert.pem"
readonly REGISTRY_HOME="/opt/container_registry"
readonly REGISTRY_SSL_DIR="${REGISTRY_HOME}/ssl"
readonly REGISTRY_DATA_DIR="/computestacks-mnt"
readonly AGENT_CONFIG_DIR="/etc/computestacks"
readonly AGENT_CONFIG_FILE="${AGENT_CONFIG_DIR}/agent.yml"
readonly AGENT_BACKUP_KEY_FILE="${AGENT_CONFIG_DIR}/backups.key"
readonly DOCKER_DROPIN="/etc/systemd/system/docker.service.d/startup.conf"
readonly HOSTS_MARKER_BEGIN="# BEGIN computestacks dev (lib/dev/single-node.sh)"
readonly HOSTS_MARKER_END="# END computestacks dev (lib/dev/single-node.sh)"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# ===========================================================================
# Options
# ===========================================================================
CONTROLLER_IP=""
CONTROLLER_PORT="3005"
VM_IP=""
NODE_HOSTNAME="csdev"
REGION="dev"
ENROLLMENT_TOKEN="${NODE_ENROLLMENT_TOKEN:-}"
SSH_PUBKEY=""
SSH_PUBKEY_FILE=""
ENROLL_ONLY="no"
SKIP_OBSERVABILITY="no"
DRY_RUN="no"

# Mutable state
FILE_CHANGED="no"        # set by write_file on every call
APT_CHANGED="no"         # set by apt_install when it actually installed
ENROLLED="no"            # set by step_16 when agent.yml carries a real hash
SELF_CHECK_FAILURES=0
SSH_TRUST_OK="no"

usage() {
  cat <<'USAGE'
ComputeStacks single-node dev environment installer (Ubuntu 26.04 "resolute").

Run as root ON THE NODE VM. Rails runs on your workstation, not here.

Usage:
  single-node.sh --controller-ip <ip> [options]

Options:
  --controller-ip <ip>    Address of the workstation running the Rails
                          controller. Required (except with --help).
  --controller-port <n>   Controller HTTP port. Default: 3005.
  --vm-ip <ip>            This VM's address, as the controller will reach it.
                          Default: autodetected from the route to the
                          controller, else the default route.
  --hostname <name>       Node hostname. Default: csdev. Must match the Node
                          row lib/tasks/setup_dev.rake creates.
  --region <name>         Region name. Default: dev. Becomes the prometheus
                          `region` label; must match setup_dev.rake.
  --token <secret>        Shared node enrollment secret. Defaults to
                          $NODE_ENROLLMENT_TOKEN from the environment. Must
                          equal the controller's NODE_ENROLLMENT_TOKEN.
  --ssh-pubkey <key>      The controller's SSH public key, as a string.
                          lib/dev/workstation.sh generates it on the
                          workstation at ~/.ssh/computestacks_dev.pub.
  --ssh-pubkey-file <p>   Read that public key from a file instead. Prefer
                          this over --ssh-pubkey when invoking over ssh: the
                          remote shell re-splits the key's three fields into
                          three arguments. Falls back to
                          <script dir>/keys/id_ed25519.pub when present.
  --enroll-only           Skip straight to enrollment: re-fetch this node's
                          agent token hash, re-render agent.yml, restart
                          cs-agent, and run the self-checks. Use this after
                          `rake setup_dev` has created the Node row.
  --skip-observability    Do not install cadvisor, prometheus or loki. Admin
                          metric/log pages then time out, and without
                          prometheus the controller rejects every order.
                          fluentd is installed regardless -- it is a hard
                          dependency of container creation, not observability.
  --dry-run               Print what would change and touch nothing.
  --help                  This text.

Everything except step 16 (enrollment) works before the controller exists.
Enrollment needs the controller to already hold a Node row for this host, so
the normal order is: run this script, run `rake setup_dev` on the workstation,
then re-run this script with --enroll-only.
USAGE
}

# ===========================================================================
# Output helpers
# ===========================================================================
log()   { printf '%s\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
warn()  { printf 'WARNING: %s\n' "$*" >&2; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

step() {
  printf '\n== %s\n' "$*"
}

is_dry_run() { [ "$DRY_RUN" = "yes" ]; }

# ===========================================================================
# Mutation helpers -- EVERY change to the system goes through one of these, so
# that --dry-run is genuinely inert.
# ===========================================================================

# Run a command, or describe it under --dry-run.
run() {
  if is_dry_run; then
    printf '  [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

# Run a shell fragment (pipelines, redirections), or describe it.
run_sh() {
  if is_dry_run; then
    printf '  [dry-run] sh -c: %s\n' "$1"
    return 0
  fi
  bash -c "$1"
}

# write_file <path> <mode>, content on stdin.
#
# Whole-file, atomic, and idempotent: sets FILE_CHANGED=yes only when the
# content actually differs from what is already there. Callers use that to
# decide whether a service needs restarting, which is what keeps a re-run from
# bouncing every container on the node.
#
# Whole-file writes (rather than the old script's `>>` appends) are what make
# this script safely re-runnable at all.
write_file() {
  local path="$1" mode="$2"
  local content tmp dir
  content="$(cat)"
  FILE_CHANGED="no"

  if [ -f "$path" ] && printf '%s\n' "$content" | cmp -s - "$path"; then
    if is_dry_run; then
      return 0
    fi
    chmod "$mode" "$path"
    return 0
  fi

  FILE_CHANGED="yes"
  if is_dry_run; then
    if [ -f "$path" ]; then
      printf '  [dry-run] rewrite %s (mode %s)\n' "$path" "$mode"
    else
      printf '  [dry-run] create %s (mode %s)\n' "$path" "$mode"
    fi
    return 0
  fi

  dir="$(dirname -- "$path")"
  [ -d "$dir" ] || mkdir -p "$dir"
  tmp="${path}.cs-tmp.$$"
  printf '%s\n' "$content" >"$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
  info "wrote $path"
}

# Append a line to a file exactly once.
append_line_once() {
  local line="$1" file="$2" mode="${3:-0644}"
  if [ -f "$file" ] && grep -qxF -- "$line" "$file" 2>/dev/null; then
    # Converge the mode even when the content is already right: a
    # pre-existing world-readable authorized_keys would otherwise keep it.
    is_dry_run || chmod "$mode" "$file"
    return 0
  fi
  if is_dry_run; then
    printf '  [dry-run] append to %s: %s\n' "$file" "$line"
    return 0
  fi
  local dir
  dir="$(dirname -- "$file")"
  [ -d "$dir" ] || mkdir -p "$dir"
  printf '%s\n' "$line" >>"$file"
  chmod "$mode" "$file"
  info "appended to $file"
}

ensure_dir() {
  local path="$1" mode="$2"
  if [ -d "$path" ]; then
    run chmod "$mode" "$path"
    return 0
  fi
  run mkdir -p "$path"
  run chmod "$mode" "$path"
}

# apt_install <hold|nohold> <spec>...   where <spec> is "pkg" or "pkg=version".
#
# The provisioner's idiom: a held package cannot be moved to a new pin, so the
# hold is RELEASED before the install and re-applied afterwards. That is what
# makes a version bump in the PINNED_VERSIONS block above actually roll through
# on a re-run. Only the pinned packages are held; the base set is not, so
# ordinary security updates still reach a dev VM. Sets APT_CHANGED=yes when
# something was actually installed.
apt_install() {
  local hold_mode="$1"; shift
  local specs=("$@")
  local todo=()
  local spec pkg ver cur

  APT_CHANGED="no"
  for spec in "${specs[@]}"; do
    pkg="${spec%%=*}"
    ver=""
    [ "$spec" != "$pkg" ] && ver="${spec#*=}"
    cur="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)"
    if [ -z "$cur" ] || { [ -n "$ver" ] && [ "$cur" != "$ver" ]; }; then
      todo+=("$spec")
    fi
  done

  if [ "${#todo[@]}" -gt 0 ]; then
    for spec in "${specs[@]}"; do
      run apt-mark unhold "${spec%%=*}" >/dev/null 2>&1 || true
    done
    run env DEBIAN_FRONTEND=noninteractive apt-get -y \
      -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
      --allow-downgrades install "${todo[@]}"
    APT_CHANGED="yes"
  fi

  if [ "$hold_mode" = "hold" ]; then
    for spec in "${specs[@]}"; do
      run apt-mark hold "${spec%%=*}" >/dev/null 2>&1 || true
    done
  fi
}

# Pull an image only when it is not already present. Every tag is pinned, so a
# version bump in PINNED_VERSIONS is the only thing that should ever move an
# image on this node.
pull_image_if_absent() {
  local image="$1"
  if docker image inspect "$image" >/dev/null 2>&1; then
    info "image present: $image"
    return 0
  fi
  run docker pull "$image"
}

# ensure_unit <unit> <unit-file-changed:yes|no>
#
# Enable always; restart only when the unit file actually changed. The pinned
# image tag is baked into each ExecStart, so bumping a version in
# PINNED_VERSIONS is what re-renders the unit, which is what restarts the
# container -- and nothing else does.
ensure_unit() {
  local unit="$1" changed="$2"
  if [ "$changed" = "yes" ]; then
    run systemctl daemon-reload
    run systemctl enable "$unit"
    run systemctl restart "$unit"
    return 0
  fi
  run systemctl enable "$unit"
  if ! systemctl is-active --quiet "$unit" 2>/dev/null; then
    run systemctl start "$unit"
  fi
}

# ===========================================================================
# Argument parsing
# ===========================================================================
parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --controller-ip)    CONTROLLER_IP="${2:-}"; shift 2 ;;
      --controller-port)  CONTROLLER_PORT="${2:-}"; shift 2 ;;
      --vm-ip)            VM_IP="${2:-}"; shift 2 ;;
      --hostname)         NODE_HOSTNAME="${2:-}"; shift 2 ;;
      --region)           REGION="${2:-}"; shift 2 ;;
      --token)            ENROLLMENT_TOKEN="${2:-}"; shift 2 ;;
      --ssh-pubkey)       SSH_PUBKEY="${2:-}"; shift 2 ;;
      --ssh-pubkey-file)  SSH_PUBKEY_FILE="${2:-}"; shift 2 ;;
      --enroll-only)      ENROLL_ONLY="yes"; shift ;;
      --skip-observability) SKIP_OBSERVABILITY="yes"; shift ;;
      --dry-run)          DRY_RUN="yes"; shift ;;
      -h|--help)          usage; exit 0 ;;
      *) usage >&2; die "unknown argument: $1" ;;
    esac
  done
}

# ===========================================================================
# Step 0 -- preflight (roles/preflight)
# ===========================================================================

# Assertions are downgraded to warnings under --dry-run so the dry run can be
# exercised from a workstation that is neither root nor Ubuntu 26.04.
assert_or_warn() {
  local ok="$1" message="$2"
  if [ "$ok" = "yes" ]; then
    return 0
  fi
  if is_dry_run; then
    warn "$message (ignored: --dry-run)"
    return 0
  fi
  die "$message"
}

# Read one field out of /etc/os-release. Parsed rather than sourced: sourcing
# would execute whatever is in the file, and shellcheck cannot follow it.
os_release_field() {
  local key="$1" value=""
  [ -r /etc/os-release ] || return 0
  value="$(grep -m1 "^${key}=" /etc/os-release 2>/dev/null | cut -d= -f2- || true)"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "$value"
}

detect_vm_ip() {
  local ip=""
  # `|| true` on every one of these: with `pipefail` set, a route lookup that
  # finds nothing fails the whole pipeline, and an unguarded command
  # substitution would then abort the script under `set -e`.
  if [ -n "$CONTROLLER_IP" ]; then
    ip="$(ip -4 route get "$CONTROLLER_IP" 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1 || true)"
  fi
  if [ -z "$ip" ]; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1 || true)"
  fi
  printf '%s' "$ip"
}

step_00_preflight() {
  step "Step 0/17  preflight"

  local is_root="no"
  [ "$(id -u)" = "0" ] && is_root="yes"
  assert_or_warn "$is_root" "this script must be run as root"

  local distro_ok="no" distro_id="" distro_ver="" distro_code=""
  distro_id="$(os_release_field ID)"
  distro_ver="$(os_release_field VERSION_ID)"
  distro_code="$(os_release_field VERSION_CODENAME)"
  [ "$distro_id" = "ubuntu" ] && [ "$distro_ver" = "26.04" ] && distro_ok="yes"
  assert_or_warn "$distro_ok" \
    "this script targets Ubuntu 26.04 (resolute); found '${distro_id:-unknown} ${distro_ver:-unknown}'"
  if [ -n "$distro_code" ] && [ "$distro_code" != "resolute" ] && [ "$distro_ok" = "yes" ]; then
    warn "expected codename 'resolute', found '$distro_code'; apt repositories below use 'resolute'"
  fi

  local arch_ok="no" arch=""
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  if [ "$arch" = "amd64" ] || [ "$arch" = "x86_64" ]; then arch_ok="yes"; fi
  assert_or_warn "$arch_ok" "this script targets amd64; found '$arch'"

  local ctl_ok="no"
  [ -n "$CONTROLLER_IP" ] && ctl_ok="yes"
  assert_or_warn "$ctl_ok" "--controller-ip is required (the workstation running Rails)"

  # Single-word, lowercase. The hostname becomes the prometheus `node` label
  # and the Node row's hostname; anything else silently breaks placement.
  local host_ok="no"
  if printf '%s' "$NODE_HOSTNAME" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
    host_ok="yes"
  fi
  assert_or_warn "$host_ok" \
    "--hostname must be a single lowercase word (got '$NODE_HOSTNAME')"

  local region_ok="no"
  if printf '%s' "$REGION" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
    region_ok="yes"
  fi
  assert_or_warn "$region_ok" "--region must be a single lowercase word (got '$REGION')"

  if [ -z "$VM_IP" ]; then
    VM_IP="$(detect_vm_ip)"
    [ -n "$VM_IP" ] && info "autodetected --vm-ip $VM_IP"
  fi
  local vm_ok="no"
  [ -n "$VM_IP" ] && vm_ok="yes"
  assert_or_warn "$vm_ok" "could not determine this VM's address; pass --vm-ip"
  [ -n "$VM_IP" ] || VM_IP="0.0.0.0"

  # The controller only has to be reachable for step 16, so this is a warning.
  if [ -n "$CONTROLLER_IP" ] && ! is_dry_run; then
    if curl -fsS -o /dev/null --max-time 5 \
        "http://${CONTROLLER_IP}:${CONTROLLER_PORT}/" 2>/dev/null; then
      info "controller reachable at http://${CONTROLLER_IP}:${CONTROLLER_PORT}/"
    else
      warn "controller did not answer at http://${CONTROLLER_IP}:${CONTROLLER_PORT}/ -- everything except enrollment (step 16) will still install"
    fi
  fi

  # Resolve the controller's SSH public key now so step 7 can report cleanly.
  if [ -z "$SSH_PUBKEY" ]; then
    if [ -z "$SSH_PUBKEY_FILE" ] && [ -r "${SCRIPT_DIR}/keys/id_ed25519.pub" ]; then
      SSH_PUBKEY_FILE="${SCRIPT_DIR}/keys/id_ed25519.pub"
    fi
    if [ -n "$SSH_PUBKEY_FILE" ]; then
      if [ -r "$SSH_PUBKEY_FILE" ]; then
        SSH_PUBKEY="$(cat "$SSH_PUBKEY_FILE")"
      else
        warn "cannot read --ssh-pubkey-file $SSH_PUBKEY_FILE"
      fi
    fi
  fi

  info "controller  ${CONTROLLER_IP}:${CONTROLLER_PORT}"
  info "node        ${NODE_HOSTNAME} (${VM_IP}), region ${REGION}"
  is_dry_run && info "MODE        dry run -- nothing will be changed"
  return 0
}

# ===========================================================================
# Step 1 -- base system (roles/common)
# ===========================================================================

# Names the base package set. NOTE: on resolute the dig/nslookup package is
# `bind9-dnsutils`; `dnsutils` DOES NOT EXIST and the old version of this
# script died on its very first apt-get install because of it. The provisioner
# still says `dnsutils` because its list predates 26.04.
#
# Dropped from the provisioner's list: python3-pip / python3-docker /
# python3-openssl (there for ansible's modules, which do not run here), man-db,
# and unattended-upgrades (a dev VM should not have packages move under it).
base_packages() {
  cat <<'EOF'
apparmor
bind9-dnsutils
ca-certificates
chrony
curl
git
gnupg
iptables
jq
net-tools
openssl
rsync
socat
sudo
sysstat
tmux
traceroute
tree
vim
wget
whois
EOF
}

render_hosts_block() {
  cat <<EOF
${HOSTS_MARKER_BEGIN}
127.0.1.1 ${NODE_HOSTNAME}
${VM_IP} ${NODE_HOSTNAME} ${REGISTRY_DOMAIN} ${LB_DOMAIN}
${CONTROLLER_IP} ${CONTROLLER_DOMAIN}
${HOSTS_MARKER_END}
EOF
}

# The node has no local resolver (PowerDNS lives in the workstation's compose
# file), so the names it has to resolve go in /etc/hosts. It needs
# registry.cstacks.local to pull from its own container registry and
# controller.cstacks.local for the haproxy `acme` backend.
#
# Managed as a marked block and rewritten in place, so a changed VM or
# controller address updates rather than accumulating stale lines.
# lib/tasks/setup_dev.rake appends its own controller.cstacks.local entry; a
# duplicate is harmless (glibc takes the first match).
# Replace our marked block in $1 (or append it if absent), leaving everything
# else byte-identical.
rewrite_hosts_block_in() {
  local target="$1" mode="$2" current stripped block
  current="$(cat "$target" 2>/dev/null || true)"
  stripped="$(printf '%s\n' "$current" | awk -v b="$HOSTS_MARKER_BEGIN" -v e="$HOSTS_MARKER_END" '
    $0 == b { skip = 1 }
    skip == 0 { print }
    $0 == e { skip = 0 }
  ')"
  block="$(render_hosts_block)"
  printf '%s\n%s\n' "$stripped" "$block" | write_file "$target" "$mode"
}

# cloud-init's hosts template. Writing the block here as well is what makes it
# survive a reboot: `manage_etc_hosts` is set by the image's USER-DATA, which
# outranks anything in /etc/cloud/cloud.cfg.d, so it cannot be turned off from
# the node side -- see pin_cloud_init(). The rendered /etc/hosts says as much
# in its own header ("make changes to the master file in
# /etc/cloud/templates/hosts.*.tmpl"), and that is the supported way to do it.
# Verified on Ubuntu 26.04 on 2026-09-12: without this the block is gone after
# one reboot and the node can no longer resolve registry.cstacks.local.
update_cloud_init_hosts_template() {
  local tmpl found=0
  for tmpl in /etc/cloud/templates/hosts.*.tmpl; do
    [ -f "$tmpl" ] || continue
    found=1
    rewrite_hosts_block_in "$tmpl" 0644
  done
  [ "$found" = "1" ] || return 0
}

update_etc_hosts() {
  rewrite_hosts_block_in /etc/hosts 0644
  update_cloud_init_hosts_template
}

# cloud-init re-applies its own hostname and re-renders /etc/hosts from
# /etc/cloud/templates/hosts.*.tmpl on EVERY boot, not just the first. A dev
# node is normally created from a cloud image, so without this both of the
# next two operations are silently undone at the first reboot:
#
#   * the hostname reverts to the image's name. node="<hostname>" is half of
#     the frozen prometheus label contract and is what the Node row records,
#     so the controller stops matching this host -- while every dashboard
#     stays green, because node_exporter keeps reporting under the label
#     baked into prometheus.yml at install time.
#   * the managed /etc/hosts block disappears, so registry.cstacks.local no
#     longer resolves and docker cannot pull from the dev registry at all.
#
# Both reproduced on Ubuntu 26.04 on 2026-09-12. This drop-in fixes only the
# hostname half; the /etc/hosts half is handled in
# update_cloud_init_hosts_template(), because manage_etc_hosts is commonly set
# by the image's user-data, which outranks /etc/cloud/cloud.cfg.d. Not a
# production concern (the provisioner builds nodes from a netboot install, not
# a cloud image), which is why there is no provisioner task to mirror.
pin_cloud_init() {
  [ -d /etc/cloud ] || return 0
  ensure_dir /etc/cloud/cloud.cfg.d 0755
  write_file /etc/cloud/cloud.cfg.d/99-computestacks.cfg 0644 <<'EOF'
# Managed by lib/dev/single-node.sh -- do not hand-edit.
# This installer owns the hostname; cloud-init must not put the image's one
# back on the next boot. See pin_cloud_init() in the installer.
#
# manage_etc_hosts is set here too, but do NOT rely on it: if the image's
# user-data sets it (XO's `ubuntu-lts` config does), user-data wins and this
# line is ignored. /etc/hosts is kept correct by writing the managed block
# into /etc/cloud/templates/hosts.*.tmpl instead.
preserve_hostname: true
manage_etc_hosts: false
EOF
  if [ "$FILE_CHANGED" = "yes" ]; then
    info "pinned cloud-init: it will no longer reset the hostname on boot"
  fi
}

step_01_base_system() {
  step "Step 1/17  base system packages, hostname and /etc/hosts"

  run env DEBIAN_FRONTEND=noninteractive apt-get -y update

  # ufw fights nftables/iptables, ntp fights chrony. Removed if present; NOT
  # an error when they are not.
  local conflicting=()
  local pkg
  for pkg in ufw ntp; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
      conflicting+=("$pkg")
    fi
  done
  if [ "${#conflicting[@]}" -gt 0 ]; then
    run env DEBIAN_FRONTEND=noninteractive apt-get -y purge "${conflicting[@]}"
  fi

  local want=()
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && want+=("$pkg")
  done < <(base_packages)
  # The base set is deliberately NOT held -- only the pinned packages are.
  apt_install nohold "${want[@]}"

  pin_cloud_init

  if [ "$(hostname 2>/dev/null || true)" != "$NODE_HOSTNAME" ]; then
    run hostnamectl set-hostname "$NODE_HOSTNAME"
  else
    info "hostname already $NODE_HOSTNAME"
  fi

  update_etc_hosts

  run systemctl enable chrony >/dev/null 2>&1 || true
  if ! systemctl is-active --quiet chrony 2>/dev/null; then
    run systemctl start chrony
  fi
}

# ===========================================================================
# Step 2 -- reboot gate (roles/common/tasks/reboot_if_required.yml)
# ===========================================================================
#
# Installing packages can pull in a new kernel and remove the running kernel's
# /lib/modules tree; modprobe of br_netfilter / nf_nat then fails and dockerd
# cannot build its firewall chains. Rather than reboot underneath the operator,
# stop here and let them reboot. A re-run resumes: every step above is
# idempotent.
step_02_reboot_gate() {
  step "Step 2/17  reboot gate"
  if [ ! -e /var/run/reboot-required ]; then
    info "no reboot required"
    return 0
  fi
  cat <<EOF

  ---------------------------------------------------------------------
  A REBOOT IS REQUIRED before the install can continue.

  The package phase installed a new kernel. Docker cannot build its
  iptables chains until this host is running it.

      reboot

  Then re-run this script with exactly the same arguments -- everything
  done so far is idempotent and will be skipped.
  ---------------------------------------------------------------------

EOF
  exit 0
}

# ===========================================================================
# Step 3 -- kernel tuning and modules (roles/node_kernel, subset)
# ===========================================================================
step_03_kernel() {
  step "Step 3/17  kernel modules and sysctls"

  # node_kernel owns cs-node.conf; the firewall step owns cs-firewall.conf.
  write_file /etc/modules-load.d/cs-node.conf 0644 <<'EOF'
# Managed by lib/dev/single-node.sh (mirrors roles/node_kernel).
nf_conntrack
br_netfilter
EOF
  local modules_changed="$FILE_CHANGED"

  # Only the subset a 6 GB dev VM benefits from. The provisioner's
  # container-density tuning is deliberately NOT ported -- in particular
  # vm.min_free_kbytes=524288, which reserves half a gigabyte on this box, and
  # the nf_conntrack hashsize module option.
  write_file /etc/sysctl.d/60-cs-node.conf 0644 <<'EOF'
# Managed by lib/dev/single-node.sh. A SUBSET of roles/node_kernel: the
# production values assume a large node and are harmful on a dev VM.

# Containers with many watchers (node, elasticsearch, ...) exhaust the
# defaults quickly.
fs.inotify.max_queued_events = 8388608
fs.inotify.max_user_instances = 8388608
fs.inotify.max_user_watches = 16777216

# Required by elasticsearch/opensearch images.
vm.max_map_count = 262144

# BBR.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  local sysctl_changed="$FILE_CHANGED"

  if [ "$modules_changed" = "yes" ]; then
    run modprobe -a nf_conntrack br_netfilter
  fi
  if [ "$sysctl_changed" = "yes" ]; then
    run sysctl --system >/dev/null
  fi
  [ "$modules_changed" = "no" ] && [ "$sysctl_changed" = "no" ] && info "unchanged"
  return 0
}

# ===========================================================================
# Step 4 -- docker engine (geerlingguy.docker + site.yml's hold/unhold)
# ===========================================================================

# Docker's packaged unit is started by the install. A drop-in left from a
# previous run pins `-H tcp://<old ip>:2376`, and if this VM's address has
# changed since (DHCP lease, rebuild) dockerd exits immediately with
# "bind: cannot assign requested address" -- before the step that would have
# rewritten it. Straight out of roles/docker_tls/tasks/clear_stale_dropin.yml.
clear_stale_docker_dropin() {
  local want_endpoint="tcp://${VM_IP}:${PORT_DOCKER}"
  if [ ! -f "$DOCKER_DROPIN" ]; then
    return 0
  fi
  if grep -qF -- "$want_endpoint" "$DOCKER_DROPIN" 2>/dev/null; then
    return 0
  fi
  warn "removing a docker drop-in that pins an address this host no longer has"
  run rm -f "$DOCKER_DROPIN"
  run systemctl daemon-reload
}

step_04_docker_engine() {
  step "Step 4/17  docker engine"

  ensure_dir /etc/apt/keyrings 0755
  if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    run_sh "curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc"
    run chmod a+r /etc/apt/keyrings/docker.asc
  else
    info "docker apt key present"
  fi

  # `resolute` IS Ubuntu 26.04 and download.docker.com publishes that suite;
  # 25.10 is `questing`, a separate suite. Pinned literally rather than read
  # from /etc/os-release so a derivative distro cannot silently pick another.
  write_file /etc/apt/sources.list.d/docker.list 0644 <<EOF
# Managed by lib/dev/single-node.sh
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu resolute stable
EOF
  if [ "$FILE_CHANGED" = "yes" ]; then
    run env DEBIAN_FRONTEND=noninteractive apt-get -y update
  fi

  clear_stale_docker_dropin

  # Each docker package carries its own version scheme -- containerd.io and
  # the buildx plugin do NOT share docker-ce's -- so each is pinned on its own.
  # docker-ce-rootless-extras is in the provisioner's list but is not installed
  # here: nothing in dev runs rootless.
  apt_install hold \
    "docker-ce=${DOCKER_CE_VERSION}" \
    "docker-ce-cli=${DOCKER_CE_VERSION}" \
    "containerd.io=${CONTAINERD_VERSION}" \
    "docker-buildx-plugin=${BUILDX_VERSION}"
  local engine_changed="$APT_CHANGED"

  run systemctl enable docker >/dev/null 2>&1 || true
  [ "$engine_changed" = "yes" ] && info "docker engine installed/updated"
  return 0
}

# ===========================================================================
# Step 5 -- /etc/docker/daemon.json (roles/docker_config)
# ===========================================================================
#
# Byte-identical to production's. Both options are SIGHUP-reloadable, which is
# why they live here and not in the ExecStart flags -- docker hard-errors when
# an option is set in both places, so nothing here may be repeated in the
# drop-in written by step 6.
#
# The storage driver is deliberately absent: resolute selects `overlayfs`
# (not `overlay2`) on its own, and pinning it here would only be a way to get
# it wrong.
#
# Registry trust is done with /etc/docker/certs.d (step 10), NOT
# `insecure-registries`, precisely so this file stays identical to production.
step_05_docker_daemon_json() {
  step "Step 5/17  /etc/docker/daemon.json"
  ensure_dir /etc/docker 0755
  write_file /etc/docker/daemon.json 0644 <<'EOF'
{
    "live-restore": true,
    "shutdown-timeout": 60
}
EOF
  if [ "$FILE_CHANGED" = "yes" ]; then
    run systemctl reload docker || run systemctl restart docker
  else
    info "unchanged"
  fi
}

# ===========================================================================
# Step 6 -- docker TCP listener (roles/docker_tls, without the TLS)
# ===========================================================================
#
# Production issues vault-backed mTLS certificates and adds --tlsverify. Dev
# deliberately does not: the socket is plain tcp://<vm ip>:2376 on a trusted
# L2. Everything else -- the drop-in path, the flags, TasksMax -- matches, so
# that a host cannot end up with two drop-ins setting a conflicting ExecStart.
step_06_docker_listener() {
  step "Step 6/17  docker TCP listener on ${VM_IP}:${PORT_DOCKER}"
  ensure_dir /etc/systemd/system/docker.service.d 0755
  write_file "$DOCKER_DROPIN" 0644 <<EOF
# Managed by lib/dev/single-node.sh (mirrors roles/docker_tls, minus TLS).
# SIGHUP-reloadable options (live-restore, shutdown-timeout) belong in
# /etc/docker/daemon.json -- docker refuses to start when an option is set in
# both places.
#
# --icc=false isolates containers on the default bridge.
# --userland-proxy=false keeps published ports on the DNAT path.
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H unix:// -H tcp://${VM_IP}:${PORT_DOCKER} --icc=false --userland-proxy=false
TasksMax=infinity
EOF
  if [ "$FILE_CHANGED" = "yes" ]; then
    run systemctl daemon-reload
    run systemctl restart docker
  else
    info "unchanged"
    if ! systemctl is-active --quiet docker 2>/dev/null; then
      run systemctl start docker
    fi
  fi
}

# ===========================================================================
# Step 7 -- ssh trust (roles/ssh_trust)
# ===========================================================================
#
# The controller manages this node over SSH as root: volumes, haproxy
# certificate deploys, LB reloads, and lib/tasks/setup_dev.rake itself. The key
# is the one lib/dev/workstation.sh generates at ~/.ssh/computestacks_dev.
step_07_ssh_trust() {
  step "Step 7/17  ssh trust for the controller"

  ensure_dir /root/.ssh 0700

  if [ -z "$SSH_PUBKEY" ]; then
    # A re-run (notably --enroll-only, which is normally invoked without the
    # key) must not claim the trust is missing when it plainly is not -- a
    # scary banner that is wrong teaches people to ignore the one that isn't.
    if [ -s /root/.ssh/authorized_keys ]; then
      info "no --ssh-pubkey given; /root/.ssh/authorized_keys is already populated, leaving it alone"
      SSH_TRUST_OK="yes"
      return 0
    fi
    warn "no controller SSH public key supplied -- pass --ssh-pubkey or --ssh-pubkey-file"
    warn "until then the controller cannot manage volumes, deploy LB certificates or run setup_dev against this node"
    return 0
  fi

  # Additive, never exclusive: an operator's own key in authorized_keys must
  # survive every run.
  append_line_once "$SSH_PUBKEY" /root/.ssh/authorized_keys 0600
  SSH_TRUST_OK="yes"
  info "controller key trusted for root"
}

# ===========================================================================
# Step 8 -- haproxy (roles/haproxy)
# ===========================================================================
#
# This step NEVER writes /etc/haproxy/haproxy.cfg. The CONTROLLER renders the
# whole file per load balancer and deploys it over SSH at runtime
# (app/views/api/stacks/load_balancers/config.erb). All this does is make sure
# every path that generated config references already exists.
haproxy_error_page() {
  cat <<'EOF'
HTTP/1.0 503 Service Unavailable
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<!DOCTYPE html>
<html>
<head>
<meta http-equiv="content-type" content="text/html;charset=UTF-8" />
<title>Service Unavailable - 503</title>
</head>
<body>
<h1>Service Unavailable - 503</h1>
<p>
Either the service you are attempting to connect to is offline,
or you have entered an invalid URL.
</p>
</body>
</html>
EOF
}

step_08_haproxy() {
  step "Step 8/17  haproxy"

  apt_install hold haproxy

  ensure_dir /etc/haproxy/certs 0700
  ensure_dir /etc/haproxy/errors 0755

  haproxy_error_page | write_file /etc/haproxy/default.http 0644

  # The distro package ships errors/<code>.http for each of these. Filling any
  # gap with the generic page keeps a missing errorfile from turning a
  # controller config push into a node that cannot start haproxy at all.
  local code
  for code in 400 403 408 500 502 504; do
    if [ ! -f "/etc/haproxy/errors/${code}.http" ]; then
      haproxy_error_page | write_file "/etc/haproxy/errors/${code}.http" 0644
    fi
  done

  # The controller's generated config carries `ssl-dh-param-file
  # /etc/haproxy/dhparam.pem` unconditionally and haproxy refuses to start when
  # it is missing. Nothing else creates it. Guarded because 2048-bit generation
  # takes a while.
  if [ ! -f /etc/haproxy/dhparam.pem ]; then
    info "generating /etc/haproxy/dhparam.pem (2048 bit, this takes a minute)"
    run_sh "openssl dhparam -out /etc/haproxy/dhparam.pem 2048 2>/dev/null"
    run chmod 0644 /etc/haproxy/dhparam.pem
  else
    info "dhparam.pem present"
  fi

  # ENABLED, NEVER STARTED. The distro's stock haproxy.cfg has no listener, so
  # a node that has never received a controller config push has nothing to
  # serve. The controller starts and reloads haproxy when it deploys the real
  # config.
  run systemctl enable haproxy >/dev/null 2>&1 || true
  info "haproxy enabled (not started -- the controller starts it with the first config push)"
}

# ===========================================================================
# Step 9 -- cstacks user and the self-signed wildcard certificate
# ===========================================================================
#
# Dev only. In production the load balancer certificate comes from ACME.
#
# lib/tasks/setup_dev.rake reads /home/cstacks/.ssl_wildcard/sharedcert.pem
# over SSH and stores it as the dev LoadBalancer's certificate, so BOTH the
# path and the file layout (private key first, then certificate -- the same
# order as lib/dev/test_wildcard_ssl/sharedcert-test-crt) are load-bearing.
#
# The old version of this script assumed the `cstacks` user already existed --
# it was inherited from a Vagrant box that was deleted in 4bd0fb9 -- so every
# path under /home/cstacks failed on a real VM.
# A certificate file counts as "present" only if it actually parses, and -- for
# the registry -- only if its SAN still names this node's address.
#
# The guard here used to be `[ -f ]` alone. An install interrupted during the
# write (Ctrl-C, dropped SSH, OOM) then left a truncated PEM that every later
# run reported as present and never repaired, because nothing re-reads it.
# setup_dev.rake does not validate it either: a non-empty file passes its
# blank-check and gets stored as the dev load balancer's certificate, so the
# damage surfaces days later as haproxy refusing to start.
pem_is_usable() {
  local file="$1" want_ip="${2:-}"
  [ -s "$file" ] || return 1
  openssl x509 -in "$file" -noout >/dev/null 2>&1 || return 1
  if [ -n "$want_ip" ]; then
    openssl x509 -in "$file" -noout -ext subjectAltName 2>/dev/null \
      | grep -qF "IP Address:${want_ip}" || return 1
  fi
  return 0
}

# The wildcard bundle must carry its private key as well as the certificate --
# haproxy needs both out of the one file.
wildcard_is_usable() {
  pem_is_usable "$1" || return 1
  grep -q -- "-----BEGIN .*PRIVATE KEY-----" "$1" || return 1
  return 0
}

step_09_wildcard_cert() {
  step "Step 9/17  cstacks user and wildcard certificate"

  if id -u "$CSTACKS_USER" >/dev/null 2>&1; then
    info "user $CSTACKS_USER exists"
  else
    run useradd --create-home --home-dir "$CSTACKS_HOME" --shell /bin/bash "$CSTACKS_USER"
  fi
  ensure_dir "$CSTACKS_HOME" 0755
  ensure_dir "$WILDCARD_DIR" 0700

  write_file "${WILDCARD_DIR}/wildcard.conf" 0644 <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = OR
L = Portland
O = CS Customer
OU = Deployment
CN = ${LB_DOMAIN}

[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.cstacks.local
EOF

  if wildcard_is_usable "$WILDCARD_PEM"; then
    info "wildcard certificate present at $WILDCARD_PEM"
  elif is_dry_run; then
    printf '  [dry-run] generate %s\n' "$WILDCARD_PEM"
  else
    [ -e "$WILDCARD_PEM" ] && warn "$WILDCARD_PEM is unreadable or incomplete -- regenerating it"
    local tmp
    tmp="$(mktemp -d)"
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -sha256 \
      -keyout "${tmp}/privkey.pem" -out "${tmp}/cert.pem" \
      -config "${WILDCARD_DIR}/wildcard.conf" -extensions v3_req 2>/dev/null
    # Key first, then certificate -- haproxy accepts either order, but
    # setup_dev.rake's fixture is key-first and the dev LB cert is compared
    # against it by eye often enough to be worth matching.
    # Assembled in the temp dir and moved into place, so an interruption
    # leaves the previous file rather than a half-written one.
    cat "${tmp}/privkey.pem" "${tmp}/cert.pem" >"${tmp}/bundle.pem"
    chmod 0600 "${tmp}/bundle.pem"
    mv -f "${tmp}/bundle.pem" "$WILDCARD_PEM"
    rm -rf "$tmp"
    info "generated $WILDCARD_PEM"
  fi

  run chown -R "${CSTACKS_USER}:${CSTACKS_USER}" "$CSTACKS_HOME"
}

# ===========================================================================
# Step 10 -- container registry host (roles/registry + acme_web's output)
# ===========================================================================
#
# Nothing runs a registry here: the CONTROLLER creates every registry container
# over DockerSSH (app/models/container_registry.rb). This step only prepares
# the filesystem those containers bind-mount, plus the certificate that
# roles/acme_web would have installed in production.
#
# The `updated_cr_cert` feature defaults to true, so the controller mounts
# /opt/container_registry/ssl as /certs and reads fullchain.pem / privkey.pem.
step_10_registry() {
  step "Step 10/17  container registry host"

  ensure_dir "$REGISTRY_DATA_DIR" 0700
  ensure_dir "$REGISTRY_HOME" 0700
  ensure_dir "$REGISTRY_SSL_DIR" 0700

  # SANs are mandatory: Go (and therefore dockerd) has ignored the CN for host
  # matching since 1.15, so the old script's CN-only certificate could never
  # have been accepted. CA:TRUE makes this a valid self-signed root, which is
  # what lets it be trusted as its own ca.crt.
  write_file "${REGISTRY_SSL_DIR}/cert.conf" 0644 <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = OR
L = Portland
O = CS Customer
OU = Deployment
CN = ${REGISTRY_DOMAIN}

[v3_req]
basicConstraints = critical, CA:TRUE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, keyCertSign
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${REGISTRY_DOMAIN}
IP.1 = ${VM_IP}
EOF

  # Regenerated when the file is missing, unparseable, OR when its SAN no
  # longer names this node's address -- cert.conf is rewritten every run, so
  # without the IP check a node whose DHCP lease changed would keep serving a
  # certificate for its old address forever while the config claimed otherwise.
  if pem_is_usable "${REGISTRY_SSL_DIR}/fullchain.pem" "$VM_IP"; then
    info "registry certificate present and valid for ${VM_IP}"
  elif is_dry_run; then
    printf '  [dry-run] generate %s/fullchain.pem\n' "$REGISTRY_SSL_DIR"
  else
    [ -e "${REGISTRY_SSL_DIR}/fullchain.pem" ] \
      && warn "registry certificate is unreadable or no longer covers ${VM_IP} -- regenerating it"
    local rtmp
    rtmp="$(mktemp -d)"
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -sha256 \
      -keyout "${rtmp}/privkey.pem" \
      -out "${rtmp}/fullchain.pem" \
      -config "${REGISTRY_SSL_DIR}/cert.conf" -extensions v3_req 2>/dev/null
    chmod 0600 "${rtmp}/privkey.pem"
    chmod 0644 "${rtmp}/fullchain.pem"
    mv -f "${rtmp}/privkey.pem" "${REGISTRY_SSL_DIR}/privkey.pem"
    mv -f "${rtmp}/fullchain.pem" "${REGISTRY_SSL_DIR}/fullchain.pem"
    rm -rf "$rtmp"
    info "generated ${REGISTRY_SSL_DIR}/fullchain.pem"
  fi

  # Trust, via /etc/docker/certs.d/<host>:<port>/ca.crt rather than
  # `insecure-registries`, so daemon.json stays identical to production's.
  # Docker looks the directory up by the exact host:port in the image
  # reference, and the controller allocates registry ports from 45000 upwards
  # in non-production, so the first few are pre-created.
  if [ -f "${REGISTRY_SSL_DIR}/fullchain.pem" ] || is_dry_run; then
    local i port dir
    for (( i = 0; i < REGISTRY_TRUST_PORT_COUNT; i++ )); do
      port=$(( REGISTRY_PORT_BEGIN + i ))
      dir="/etc/docker/certs.d/${REGISTRY_DOMAIN}:${port}"
      ensure_dir "$dir" 0755
      if is_dry_run; then
        printf '  [dry-run] install %s/ca.crt\n' "$dir"
      else
        install -m 0644 "${REGISTRY_SSL_DIR}/fullchain.pem" "${dir}/ca.crt"
      fi
    done
    info "docker trusts ${REGISTRY_DOMAIN} on ports ${REGISTRY_PORT_BEGIN}-$(( REGISTRY_PORT_BEGIN + REGISTRY_TRUST_PORT_COUNT - 1 ))"

    # Deliberately NOT added to the system trust store. The plan specified
    # certs.d instead of `insecure-registries`, and certs.d covers every
    # registry the controller will actually allocate. This certificate is a
    # self-signed CA:TRUE root, so anyone holding privkey.pem could mint a
    # trusted certificate for ANY host this node talks to -- not a trade worth
    # making for a registry that lands outside the port window. Widen
    # REGISTRY_TRUST_PORT_COUNT instead if that ever happens.
  fi
}

# ===========================================================================
# Step 11 -- node_exporter (roles/node_exporter)
# ===========================================================================
#
# The distro package. Binds :9100 on all interfaces, which is what the
# controller's MetricClient path needs. Pinned, then held so an upgrade cannot
# swap the exporter under a live scrape -- but a dev VM's archive moves, so a
# pin that no longer resolves falls back to whatever resolute currently ships
# rather than failing the install.
step_11_node_exporter() {
  step "Step 11/17  node_exporter"

  local spec="prometheus-node-exporter"
  if apt-cache madison prometheus-node-exporter 2>/dev/null \
      | grep -qF " ${NODE_EXPORTER_APT_VERSION} "; then
    spec="prometheus-node-exporter=${NODE_EXPORTER_APT_VERSION}"
  else
    warn "prometheus-node-exporter ${NODE_EXPORTER_APT_VERSION} is not in the archive; installing whatever resolute ships"
  fi

  apt_install hold "$spec"
  run systemctl enable prometheus-node-exporter >/dev/null 2>&1 || true
  if ! systemctl is-active --quiet prometheus-node-exporter 2>/dev/null; then
    run systemctl start prometheus-node-exporter
  fi
}

# ===========================================================================
# Step 12 -- image preloads (roles/node_observability/tasks/preload_images.yml)
# ===========================================================================
#
# Images the controller expects to already be on a node when it schedules work
# (backup, restore, bastion). Pulled only when absent -- every tag is pinned,
# so a bump in PINNED_VERSIONS is the only thing that should move one.
step_12_preload_images() {
  step "Step 12/17  preload container images"
  local image
  for image in "$BORG_IMAGE" "$BASTION_IMAGE" "$XTRABACKUP24_IMAGE" "$XTRABACKUP80_IMAGE"; do
    pull_image_if_absent "$image"
  done
}

# ===========================================================================
# Step 13 -- observability (roles/node_observability + metrics + loki)
# ===========================================================================
#
# Production splits this across two hosts; dev collapses it onto one. All four
# containers run on the HOST network, so there is no `ops` bridge, no published
# ports to DNAT, and nothing for the (absent) host firewall to filter.
#
# None of it is truly optional:
#   * setup_dev.rake hard-wires MetricClient -> <vm ip>:9090 and LogClient ->
#     <vm ip>:3100, so without prometheus and loki every admin page eats a
#     timeout.
#   * every tenant container is created with fluentd-address
#     tcp://localhost:9432, so without fluentd container CREATION fails.
# --skip-observability exists for people who genuinely do not need any of it.

install_cadvisor() {
  pull_image_if_absent "$CADVISOR_IMAGE"
  # NOTE: the container name `cadvisor` is a CONTRACT -- the controller's
  # prometheus alert rules carry an ignore-list matched on it.
  # The backslashes below are doubled so they survive the here-document and
  # land in the unit file as systemd line continuations.
  write_file /etc/systemd/system/cadvisor.service 0644 <<EOF
[Unit]
# Managed by lib/dev/single-node.sh (mirrors roles/node_observability).
Description=cAdvisor container metrics exporter
Documentation=https://github.com/google/cadvisor
Requires=docker.service
After=docker.service
DefaultDependencies=no

[Service]
Type=simple
# The image tag is baked into this unit on purpose: bumping CADVISOR_IMAGE
# re-renders the unit, which is what restarts the container -- and nothing
# else does.
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker kill cadvisor 2>/dev/null'
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker rm cadvisor 2>/dev/null'
ExecStart=/usr/bin/env docker run --rm --name cadvisor \\
      --log-driver=none \\
      --network=host \\
      --privileged \\
      --label com.computestacks.role=system \\
      -v /:/rootfs:ro \\
      -v /var/run:/var/run:ro \\
      -v /sys:/sys:ro \\
      -v /var/lib/docker/:/var/lib/docker:ro \\
      -v /dev/disk/:/dev/disk:ro \\
      -v /etc/machine-id:/etc/machine-id:ro \\
      --device=/dev/kmsg \\
      ${CADVISOR_IMAGE} \\
      -listen_ip=0.0.0.0 \\
      -port=${PORT_CADVISOR}

ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker kill cadvisor 2>/dev/null'
ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker rm cadvisor 2>/dev/null'
Restart=always
RestartSec=30
SyslogIdentifier=cadvisor

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF
  ensure_unit cadvisor.service "$FILE_CHANGED"
}

install_prometheus() {
  pull_image_if_absent "$PROMETHEUS_IMAGE"
  ensure_dir /etc/prometheus 0755

  # THE LABEL CONTRACT. node_metrics.rb#metric_selector matches
  # node="<hostname>",region="<region>",job=~"node-exporter" exactly. Wrong
  # labels here silently zero this node's cpu/memory and reject every order,
  # while prometheus, the exporter and the scrape all look healthy.
  #
  # Production renders these as per-AZ file_sd fragments written by the metrics
  # host; one node needs no service discovery, so they are static targets.
  # alerting / rule_files are dropped with alertmanager.
  write_file /etc/prometheus/prometheus.yml 0644 <<EOF
---
# Managed by lib/dev/single-node.sh (mirrors roles/metrics, minus alerting).
global:
  scrape_interval: 10s
  evaluation_interval: 10s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['127.0.0.1:${PORT_PROMETHEUS}']

  # job_name AND both labels are a frozen contract -- see the comment above.
  - job_name: node-exporter
    static_configs:
      - targets: ['127.0.0.1:${PORT_NODE_EXPORTER}']
        labels:
          region: "${REGION}"
          node: "${NODE_HOSTNAME}"

  - job_name: cadvisor
    static_configs:
      - targets: ['127.0.0.1:${PORT_CADVISOR}']
        labels:
          region: "${REGION}"
          node: "${NODE_HOSTNAME}"

  # Down until the controller pushes a load balancer configuration -- the
  # distro's stock haproxy.cfg has no listener at all. That is expected.
  - job_name: haproxy
    static_configs:
      - targets: ['127.0.0.1:${PORT_HAPROXY_STATS}']
        labels:
          region: "${REGION}"
          node: "${NODE_HOSTNAME}"
EOF
  local config_changed="$FILE_CHANGED"

  write_file /etc/systemd/system/prometheus.service 0644 <<EOF
[Unit]
# Managed by lib/dev/single-node.sh (mirrors roles/metrics).
Description=Prometheus
Requires=docker.service
After=docker.service
DefaultDependencies=no

[Service]
Type=simple
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker kill prometheus 2>/dev/null'
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker rm prometheus 2>/dev/null'
# Host network rather than production's \`ops\` bridge: this node is also the
# metrics host in dev, and the controller dials :${PORT_PROMETHEUS} on the VM
# address directly (no nginx TLS vhost, no basic auth).
ExecStart=/usr/bin/env docker run --rm --name prometheus \\
      --log-driver=none \\
      --network=host \\
      --label com.computestacks.role=system \\
      -v prometheus-data:/prometheus \\
      -v /etc/prometheus:/etc/prometheus \\
      ${PROMETHEUS_IMAGE}

ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker kill prometheus 2>/dev/null'
ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker rm prometheus 2>/dev/null'
Restart=always
RestartSec=30
SyslogIdentifier=prometheus

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF
  local unit_changed="$FILE_CHANGED"

  local changed="no"
  { [ "$config_changed" = "yes" ] || [ "$unit_changed" = "yes" ]; } && changed="yes"
  ensure_unit prometheus.service "$changed"
}

install_loki() {
  pull_image_if_absent "$LOKI_IMAGE"
  ensure_dir /etc/loki 0755

  # Copied from roles/loki/files/loki-config.yml. Keep it byte-compatible with
  # the fleet's -- the controller queries the Loki API v1 and this is the same
  # loki version production runs.
  write_file /etc/loki/loki-config.yml 0644 <<'EOF'
---
auth_enabled: false

server:
  http_listen_port: 3100
  http_server_read_timeout: 1000s
  http_server_write_timeout: 1000s
  http_server_idle_timeout: 1000s
  log_level: info

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_encoding: snappy
  chunk_idle_period: 1h
  chunk_target_size: 1048576
  chunk_retain_period: 30s
  max_transfer_retries: 0
  wal:
    dir: /loki/ruler-wal

schema_config:
  configs:
    - from: 2020-05-15
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb:
    directory: /loki/index

  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  ingestion_rate_mb: 30
  ingestion_burst_size_mb: 60

chunk_store_config:
  max_look_back_period: 336h

table_manager:
  retention_deletes_enabled: true
  retention_period: 336h
  chunk_tables_provisioning:
    inactive_read_throughput: 10
    inactive_write_throughput: 10
    provisioned_read_throughput: 50
    provisioned_write_throughput: 20
  index_tables_provisioning:
    inactive_read_throughput: 10
    inactive_write_throughput: 10
    provisioned_read_throughput: 50
    provisioned_write_throughput: 20
EOF
  local config_changed="$FILE_CHANGED"

  # Container name `loki-logs` matches production (and the controller's
  # alert ignore-list).
  write_file /etc/systemd/system/loki.service 0644 <<EOF
[Unit]
# Managed by lib/dev/single-node.sh (mirrors roles/loki).
Description=Loki
Requires=docker.service
After=docker.service
DefaultDependencies=no

[Service]
Type=simple
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker kill loki-logs 2>/dev/null'
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker rm loki-logs 2>/dev/null'
# Host network: fluentd on this node ships to 127.0.0.1:${PORT_LOKI} and the
# controller's LogClient dials the VM address. No nginx vhost, no basic auth.
ExecStart=/usr/bin/env docker run --rm --name loki-logs \\
      --log-driver=none \\
      --network=host \\
      --label com.computestacks.role=system \\
      -v loki-data:/loki \\
      -v /etc/loki/loki-config.yml:/etc/loki/local-config.yaml \\
      ${LOKI_IMAGE}

ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker kill loki-logs 2>/dev/null'
ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker rm loki-logs 2>/dev/null'
Restart=always
RestartSec=30
SyslogIdentifier=loki

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF
  local unit_changed="$FILE_CHANGED"

  local changed="no"
  { [ "$config_changed" = "yes" ] || [ "$unit_changed" = "yes" ]; } && changed="yes"
  ensure_unit loki.service "$changed"
}

install_fluentd() {
  pull_image_if_absent "$FLUENTD_LOKI_IMAGE"
  ensure_dir /etc/fluentd 0750

  # The `\$` escapes below are deliberate: this is an unquoted here-document so
  # the ports interpolate, and fluentd's record accessors ($.foo, $['foo'])
  # would otherwise be eaten by the shell -- $['...'] in particular is bash
  # arithmetic-expansion syntax.
  #
  # Production points this at the site's loki vhost over TLS with basic auth.
  # Dev has neither, and loki is on this same host, so the URL is loopback and
  # the credentials are gone -- which is also why there is no loki.env here.
  write_file /etc/fluentd/fluent.conf 0644 <<EOF
# Managed by lib/dev/single-node.sh (mirrors roles/node_observability).
<source>
  @type  forward
  @id    input1
  @label @mainstream
  # Loopback only: docker's fluentd log driver dials this from the same host.
  bind   127.0.0.1
  port   ${PORT_FLUENTD}
</source>

<filter **>
  @type stdout
</filter>

<label @mainstream>
  <match **.**>
    @type loki
    url "http://127.0.0.1:${PORT_LOKI}"
    remove_keys container_name, container_id, source
    extra_labels {"job":"fluentd"}
    flush_interval 10s
    flush_at_shutdown true
    buffer_chunk_limit 1m
    <label>
      container_name \$.container_name
    </label>
    <label>
      project_id \$['com.computestacks.deployment_id']
    </label>
    <label>
      service_id \$['com.computestacks.service_id']
    </label>
  </match>
</label>
EOF
  local config_changed="$FILE_CHANGED"

  # NOTE: the container name `fluentd` is a CONTRACT -- see cadvisor above.
  write_file /etc/systemd/system/fluentd.service 0644 <<EOF
[Unit]
# Managed by lib/dev/single-node.sh (mirrors roles/node_observability).
Description=fluentd tenant log shipper (loki output)
Documentation=https://github.com/grafana/loki/tree/main/clients/cmd/fluentd
Requires=docker.service
After=docker.service
DefaultDependencies=no

[Service]
Type=simple
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker kill fluentd 2>/dev/null'
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker rm fluentd 2>/dev/null'
ExecStart=/usr/bin/env docker run --rm --name fluentd \\
      --log-driver=none \\
      --network=host \\
      --label com.computestacks.role=system \\
      -v /etc/fluentd/fluent.conf:/fluentd/etc/fluent.conf:ro \\
      ${FLUENTD_LOKI_IMAGE}

ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker stop fluentd 2>/dev/null'
Restart=always
# Every tenant container on this node logs through here, so a crash loop backs
# off rather than hammering docker.
RestartSec=30
SyslogIdentifier=fluentd

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF
  local unit_changed="$FILE_CHANGED"

  local changed="no"
  { [ "$config_changed" = "yes" ] || [ "$unit_changed" = "yes" ]; } && changed="yes"
  ensure_unit fluentd.service "$changed"
}

step_13_observability() {
  step "Step 13/17  observability (cadvisor, prometheus, loki, fluentd)"
  if [ "$SKIP_OBSERVABILITY" = "yes" ]; then
    warn "--skip-observability: NOT installing cadvisor, prometheus or loki"
    warn "admin metric/log pages will time out; orders are rejected without prometheus"
  else
    install_cadvisor
    install_prometheus
    install_loki
  fi
  # fluentd is NOT optional and is deliberately exempt from the flag. Every
  # tenant container is created with --log-driver fluentd --log-opt
  # fluentd-address tcp://localhost:${PORT_FLUENTD}, so with no listener there
  # `docker run` fails outright and the node cannot host anything at all.
  # Without loki it simply buffers and retries; that is survivable, a dead
  # container create is not.
  install_fluentd
}

# ===========================================================================
# Step 14 -- firewall (roles/firewall, "Option A")
# ===========================================================================
#
# Option A: NO host firewall table at all. nftables is installed for tooling
# only. The box is on a trusted L2 with no tailnet, so the provisioner's entire
# source-restriction machinery collapses to nothing useful here -- and Option A
# satisfies the three never-break rules trivially:
#
#   * never `flush ruleset`     (would destroy docker's iptables-nft tables
#                                and cs-agent's own cs_agent table)
#   * never a forward-hook drop chain (would black-hole every published
#                                tenant port)
#   * never re-create the legacy expose-ports / container-inbound chains
#
# cs-agent still renders its own cs_agent DNAT table and asserts the three
# DOCKER-USER isolation rules, which is what makes published-port and
# cross-project behaviour match production. THIS STEP MUST NOT WRITE THOSE
# RULES -- the old script hand-wrote two of the three and got the order wrong.
# All it has to do is make sure xt_physdev is loaded, because isolation rule 1
# matches `-m physdev --physdev-is-bridged`.
step_14_firewall() {
  step "Step 14/17  firewall (no host table -- modules only)"

  # Installed for tooling only, and NOT held: nothing here depends on a
  # particular nft version.
  apt_install nohold nftables

  write_file /etc/modules-load.d/cs-firewall.conf 0644 <<'EOF'
# Managed by lib/dev/single-node.sh (mirrors roles/firewall).
#   nf_tables    -- docker's iptables-nft backend and cs-agent's cs_agent table
#   nf_conntrack -- ct state matching
#   xt_physdev   -- cs-agent DOCKER-USER isolation rule 1 matches
#                   `-m physdev --physdev-is-bridged`
nf_tables
nf_conntrack
xt_physdev
EOF
  if [ "$FILE_CHANGED" = "yes" ]; then
    run modprobe -a nf_tables nf_conntrack xt_physdev
  else
    # Cheap, and it covers a module that was unloaded since the last boot.
    if ! lsmod 2>/dev/null | grep -q '^xt_physdev'; then
      run modprobe xt_physdev
    fi
  fi

  # The distro nftables.service starts with `flush ruleset`, which would
  # destroy docker's tables and cs-agent's cs_agent table on every boot. We
  # ship no table, so there is nothing for it to load -- disable it if some
  # image enabled it.
  if systemctl is-enabled --quiet nftables 2>/dev/null; then
    warn "disabling nftables.service -- its 'flush ruleset' would wipe docker's and cs-agent's tables at boot"
    run systemctl disable nftables
  fi

  info "no cs_static table shipped; INPUT policy left at accept (dev)"
}

# ===========================================================================
# Step 15 -- cs-agent package (roles/cs_agent/tasks/install.yml)
# ===========================================================================
#
# Native deb under systemd. The unit ships in the package; this script does not
# write one. (The old version of this script ran
# ghcr.io/computestacks/backup-agent:1.8 as a container under a hand-written
# unit -- that is the v2 agent and it is wrong on every v3 interface.)
step_15_cs_agent() {
  step "Step 15/17  cs-agent ${CS_AGENT_VERSION}"

  ensure_dir /etc/apt/keyrings 0755
  if [ ! -f /etc/apt/keyrings/computestacks.asc ]; then
    run_sh "curl -fsSL https://repo.computestacks.com/public/computestacks.gpg.asc -o /etc/apt/keyrings/computestacks.asc"
    run chmod 0644 /etc/apt/keyrings/computestacks.asc
  fi
  # apt refuses an ASCII-armored key in signed-by, so it is dearmored.
  if [ ! -f /etc/apt/keyrings/computestacks.gpg ]; then
    run_sh "gpg --batch --yes --dearmor --output /etc/apt/keyrings/computestacks.gpg /etc/apt/keyrings/computestacks.asc"
    run chmod 0644 /etc/apt/keyrings/computestacks.gpg
  fi

  write_file /etc/apt/sources.list.d/computestacks.list 0644 <<'EOF'
# Managed by lib/dev/single-node.sh
deb [signed-by=/etc/apt/keyrings/computestacks.gpg] https://repo.computestacks.com/public stable main
EOF
  if [ "$FILE_CHANGED" = "yes" ]; then
    run env DEBIAN_FRONTEND=noninteractive apt-get -y update
  fi

  apt_install hold "cs-agent=${CS_AGENT_VERSION}"

  ensure_dir "$AGENT_CONFIG_DIR" 0750
}

# ===========================================================================
# Step 16 -- enrollment and agent.yml
# ===========================================================================

# Read any 64-hex admin token hash already in agent.yml. This runs FIRST and
# unconditionally: an EMPTY admin_token_hash disables the admin scope outright
# and the controller loses the node permanently, so a re-run that cannot reach
# the controller must keep what is already there rather than blank it.
existing_admin_token_hash() {
  [ -f "$AGENT_CONFIG_FILE" ] || return 0
  grep -oE 'admin_token_hash:[[:space:]"'"'"']*[0-9a-f]{64}' "$AGENT_CONFIG_FILE" 2>/dev/null \
    | grep -oE '[0-9a-f]{64}' | head -n1 || true
}

# The address the controller will see this request coming from. Node identity
# is by SOURCE IP, matched against the Node row's primary_ip OR public_ip.
source_address_to_controller() {
  ip -4 route get "$CONTROLLER_IP" 2>/dev/null \
    | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1 || true
}

explain_enrollment_404() {
  local src
  src="$(source_address_to_controller)"
  cat >&2 <<EOF

  The controller answered 404: it has no Node row whose primary_ip or
  public_ip matches the address this request came from.

    source address this node used : ${src:-unknown}
    --vm-ip passed to this script : ${VM_IP}
    node hostname                 : ${NODE_HOSTNAME}

  Identity on this route is by SOURCE IP, not by hostname and not by the
  token. Check, in order:

    1. Has \`bundle exec rake setup_dev\` been run on the workstation? It is
       what creates the Node row (hostname ${NODE_HOSTNAME}, primary_ip and
       public_ip both set to DEV_VM_IP).
    2. Does DEV_VM_IP in the workstation's .envrc equal ${VM_IP}?
    3. If the two addresses above differ, this node is leaving by a different
       interface than the one the Node row names. Re-run with
       --vm-ip <that address>, or fix the Node row.
    4. If anything NATs between this node and the controller, the controller
       sees the NAT address; put that in the Node row's public_ip.

EOF
}

explain_enrollment_401() {
  cat >&2 <<EOF

  The controller answered 401. From this side those two causes are
  INDISTINGUISHABLE:

    * the --token / NODE_ENROLLMENT_TOKEN given here does not match the
      controller's, OR
    * NODE_ENROLLMENT_TOKEN is BLANK in the controller's environment, in
      which case it rejects every request regardless of what is presented.

  Check both: \`echo \$NODE_ENROLLMENT_TOKEN\` in the shell running the
  controller (it must be non-empty and identical to the value used here), and
  remember that .envrc changes need the Rails processes restarted.

EOF
}

fetch_admin_token_hash() {
  local url body code
  url="http://${CONTROLLER_IP}:${CONTROLLER_PORT}/api/system/nodes/agent_token_hash"
  body="$(mktemp)"
  # Assign-then-override rather than `|| printf '000'`: on a transport failure
  # curl writes its own "000" to stdout AND exits non-zero, so appending
  # another would produce "000000".
  code="$(curl -sS -o "$body" -w '%{http_code}' --max-time 15 \
    -H "Authorization: Bearer ${ENROLLMENT_TOKEN}" \
    -H "Accept: application/json" \
    "$url" 2>/dev/null)" || code="000"

  case "$code" in
    200)
      grep -oE '[0-9a-f]{64}' "$body" | head -n1 || true
      ;;
    401)
      explain_enrollment_401
      ;;
    404)
      explain_enrollment_404
      ;;
    000)
      printf '\n  Could not reach %s at all. Is the controller running (./bin/dev) and is %s reachable from this node?\n\n' \
        "$url" "$CONTROLLER_IP" >&2
      ;;
    *)
      printf '\n  The controller answered HTTP %s for %s.\n\n' "$code" "$url" >&2
      ;;
  esac
  rm -f "$body"
}

# agent.yml, cs-agent v3 schema EXACTLY. The schema is cs-agent's
# config/config.go, NOT the upstream agent.sample.yml, which is wrong in ways
# that fail silently. Things the old script got wrong and that must stay right:
#
#   * NO `consul:` block (Consul was retired in the v3 cutover)
#   * NO `docker: version:` block (dead)
#   * backups.borg.compression, never `compress`
#   * `mariadb:` is TOP LEVEL, never nested under backups
#   * no NFS keys anywhere -- v3 is SSH/borg only
#   * metadata.listen_addr is <vm ip>:8500; the PORT is baked into customer
#     containers via metadata.internal and cannot move
#
# Only installer-owned keys are written. Everything else keeps the agent's
# compiled-in default (prune/compact schedules, borg lock waits, changelog and
# task retention, metadata.max_body_bytes). Adding a key here means owning it
# forever, so don't.
render_agent_yml() {
  local hash="$1" backups_key="$2"
  write_file "$AGENT_CONFIG_FILE" 0600 <<EOF
---
# Managed by lib/dev/single-node.sh -- do not hand-edit.
# cs-agent v${CS_AGENT_VERSION} configuration. Schema: cs-agent config/config.go.
host:
  iptables-cmd: "iptables"
  ip6tables-cmd: "ip6tables"

store:
  data_dir: "/var/lib/cs-agent"

# No \`computestacks:\` block. It is optional (only the agent's own enrolment
# snippet parses it) and this script enrolls over the controller's HTTP API
# instead.

metadata:
  # Port ${PORT_AGENT} is baked into customer containers via
  # metadata.internal:${PORT_AGENT} and cannot move; only the bind address varies.
  listen_addr: "${VM_IP}:${PORT_AGENT}"
  admin_token_hash: "${hash}"

queue:
  numworkers: 3

backups:
  # There is no backup server in a dev environment. \`key\` is written anyway
  # so that adding one later is not a new decision.
  enabled: false
  key: "${backups_key}"

# TOP-LEVEL, not nested under backups: the agent reads \`mariadb.*\`.
mariadb:
  lock_wait:
    query_type: "ALL"
    timeout: "60"
  long_queries:
    query_type: "SELECT"
    timeout: "20"
EOF
}

step_16_enrollment() {
  step "Step 16/17  enrollment and agent.yml"

  local existing_hash hash="" backups_key=""
  existing_hash="$(existing_admin_token_hash)"
  [ -n "$existing_hash" ] && info "agent.yml already carries an admin token hash"

  # Stable across runs: generated once, then re-read.
  if [ -f "$AGENT_BACKUP_KEY_FILE" ]; then
    backups_key="$(cat "$AGENT_BACKUP_KEY_FILE")"
  elif is_dry_run; then
    backups_key="<generated on first real run>"
  else
    backups_key="$(openssl rand -hex 32)"
    printf '%s\n' "$backups_key" | write_file "$AGENT_BACKUP_KEY_FILE" 0600
  fi

  if is_dry_run; then
    printf '  [dry-run] fetch the admin token hash from http://%s:%s/api/system/nodes/agent_token_hash\n' \
      "$CONTROLLER_IP" "$CONTROLLER_PORT"
    render_agent_yml "${existing_hash:-<fetched>}" "$backups_key"
    ENROLLED="yes"
    return 0
  fi

  if [ -z "$ENROLLMENT_TOKEN" ]; then
    warn "no enrollment token: pass --token or export NODE_ENROLLMENT_TOKEN (it must match the controller's)"
  else
    hash="$(fetch_admin_token_hash)"
  fi

  if [ -n "$hash" ]; then
    info "fetched this node's admin token hash from the controller"
  elif [ -n "$existing_hash" ]; then
    warn "keeping the admin token hash already in agent.yml -- an empty hash would disable the admin scope and the controller would lose this node"
    hash="$existing_hash"
  else
    cat >&2 <<EOF

  ---------------------------------------------------------------------
  NOT ENROLLED. agent.yml has NOT been written and cs-agent will not
  start -- which is the safe outcome: an agent with an empty
  admin_token_hash serves no admin scope at all and the controller
  cannot manage it.

  This is the EXPECTED result on a first run, because enrollment is the
  one step that needs the controller to already hold a Node row.

  Finish on the workstation:

      bundle exec rake setup_dev

  then come back here and run:

      $0 --enroll-only --controller-ip ${CONTROLLER_IP} \\
          --vm-ip ${VM_IP} --token <the same NODE_ENROLLMENT_TOKEN>

  --token is not optional. ssh does not forward environment variables, so
  running this over ssh without it enrolls nothing and exits 1.
  ---------------------------------------------------------------------

EOF
    ENROLLED="no"
    return 0
  fi

  render_agent_yml "$hash" "$backups_key"
  local config_changed="$FILE_CHANGED"
  ENROLLED="yes"

  # The agent re-reads agent.yml only at startup. A restart is cheap: it does
  # not touch running containers.
  run systemctl daemon-reload
  run systemctl enable cs-agent >/dev/null 2>&1 || true
  if [ "$config_changed" = "yes" ]; then
    run systemctl restart cs-agent
  elif ! systemctl is-active --quiet cs-agent 2>/dev/null; then
    run systemctl start cs-agent
  fi
}

# ===========================================================================
# Step 17 -- self-checks (roles/validate)
# ===========================================================================
check_pass() { printf '  PASS  %s\n' "$*"; }
check_fail() {
  printf '  FAIL  %s\n' "$*"
  SELF_CHECK_FAILURES=$(( SELF_CHECK_FAILURES + 1 ))
}
check_skip() { printf '  SKIP  %s\n' "$*"; }

check_unit_active() {
  local unit="$1"
  if systemctl is-active --quiet "$unit" 2>/dev/null; then
    check_pass "$unit is active"
  else
    check_fail "$unit is NOT active -- systemctl status $unit; journalctl -u $unit -n 50"
  fi
}

# haproxy is enabled but deliberately NOT started: the distro's stock config
# has no listener. Asserting is-active here would fail on a correct install.
# Enabled is the thing that matters: this script never STARTS haproxy, but the
# distro package does at install time, exactly as it does in production. A
# running haproxy on the stock config binds nothing, so both states are fine --
# claiming "not started" when it plainly is would just teach people to distrust
# these checks.
check_unit_enabled() {
  local unit="$1"
  if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      check_pass "$unit is enabled (running on the stock config, which binds nothing)"
    else
      check_pass "$unit is enabled (the controller starts it with the real config)"
    fi
  else
    check_fail "$unit is NOT enabled -- it must come back after a reboot"
  fi
}

# A 401 is the SUCCESS condition. Every cs-agent v3 handler is wrapped in
# requireCustomer/requireAdmin and an unauthenticated request is answered 401,
# so 401 proves both that the port is open and that cs-agent is what is
# answering on it.
# Probe a REAL admin endpoint, not `/`. cs-agent 3.3.0 has no route at `/` and
# answers 404 there whether or not auth is working, so a probe of `/` could
# never pass -- verified against a live agent on 2026-09-12.
# /v1/admin/changelog is what the controller polls most, and it answers 401
# with no credentials: exactly the "up and demanding auth" signal this wants.
# Retried, because the listener binds a moment after systemd calls the unit
# active and a single immediate probe gets '000'.
check_agent_http() {
  local code="" i
  for i in $(seq 1 10); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
      "http://${VM_IP}:${PORT_AGENT}/v1/admin/changelog?since=0&limit=1" 2>/dev/null)" || code="000"
    [ "$code" = "401" ] && break
    sleep 2
  done
  if [ "$code" = "401" ]; then
    check_pass "cs-agent answers 401 on ${VM_IP}:${PORT_AGENT} (expected -- it is up and demanding auth)"
  else
    check_fail "cs-agent on ${VM_IP}:${PORT_AGENT} returned '${code}', expected 401. Check metadata.listen_addr in ${AGENT_CONFIG_FILE}"
  fi
}

# The controller's own placement query, which is the only form of this check
# that matters: node_metrics.rb matches these labels exactly, and getting them
# wrong rejects every order while every dashboard stays green.
check_prometheus_labels() {
  local query url attempt body
  query="count(node_cpu_seconds_total%7Bnode%3D%22${NODE_HOSTNAME}%22%2Cregion%3D%22${REGION}%22%2Cjob%3D%22node-exporter%22%7D)"
  url="http://127.0.0.1:${PORT_PROMETHEUS}/api/v1/query?query=${query}"
  for attempt in 1 2 3 4 5 6; do
    body="$(curl -sS --max-time 10 "$url" 2>/dev/null || true)"
    if printf '%s' "$body" | grep -q '"result":\[{'; then
      check_pass "prometheus answers the placement query for node=${NODE_HOSTNAME},region=${REGION}"
      return 0
    fi
    if [ "$attempt" -lt 6 ]; then
      sleep 5
    fi
  done
  check_fail "prometheus returned no data for node=\"${NODE_HOSTNAME}\",region=\"${REGION}\",job=\"node-exporter\" -- check the labels in /etc/prometheus/prometheus.yml"
}

# cs-agent >= 3.1.0 asserts all three, in this order, on every reconcile.
# Order matters: rule 2 must sit above the DROP or published ports become
# unreachable across projects, and rule 1 must sit above both or intra-project
# L2 traffic dies.
# cs-agent asserts these itself shortly AFTER its listener comes up, so wait
# rather than sample once -- a fresh enrollment otherwise reports missing rules
# on a node that is about to be perfectly correct.
#
# Wait for ALL THREE, not for any one of them. The agent does not write them
# top-to-bottom: the br-+ DROP rule appears before the physdev RETURN is
# prepended above it, so treating DROP as the "done" sentinel samples a
# half-written chain and reports rule 1 missing on a node that is fine one
# second later. Observed on 2026-09-12.
docker_user_rule_lines() {
  local rules="$1" which="$2"
  case "$which" in
    physdev) printf '%s\n' "$rules" | grep -n -- 'physdev-is-bridged' | grep -- '-j RETURN' | head -n1 | cut -d: -f1 ;;
    dnat)    printf '%s\n' "$rules" | grep -n -- '--ctstate DNAT'     | grep -- '-j RETURN' | head -n1 | cut -d: -f1 ;;
    drop)    printf '%s\n' "$rules" | grep -n -- '-i br-+ -o br-+ -j DROP' | head -n1 | cut -d: -f1 ;;
  esac
  return 0
}

check_docker_user_rules() {
  local rules="" l1="" l2="" l3="" i
  for i in $(seq 1 20); do
    rules="$(iptables -S DOCKER-USER 2>/dev/null || true)"
    l1="$(docker_user_rule_lines "$rules" physdev)"
    l2="$(docker_user_rule_lines "$rules" dnat)"
    l3="$(docker_user_rule_lines "$rules" drop)"
    if [ -n "$l1" ] && [ -n "$l2" ] && [ -n "$l3" ]; then break; fi
    sleep 2
  done
  if [ -z "$rules" ]; then
    check_fail "iptables -S DOCKER-USER produced nothing -- is docker running?"
    return 0
  fi
  # l1/l2/l3 come from the settling loop above. A MISSING rule is the failure
  # this check exists to report, which is why the helper always returns 0.
  if [ -z "$l1" ] || [ -z "$l2" ] || [ -z "$l3" ]; then
    check_fail "DOCKER-USER is missing one of cs-agent's three isolation rules (physdev RETURN / DNAT RETURN / br-+ DROP). cs-agent renders these -- do NOT add them by hand."
    printf '%s\n' "$rules" | sed 's/^/        /'
    return 0
  fi
  if [ "$l1" -lt "$l2" ] && [ "$l2" -lt "$l3" ]; then
    check_pass "DOCKER-USER carries cs-agent's three isolation rules, in order"
  else
    check_fail "DOCKER-USER carries all three isolation rules but in the WRONG ORDER (physdev=${l1}, DNAT=${l2}, DROP=${l3})"
  fi
}

step_17_self_checks() {
  step "Step 17/17  self-checks"

  if is_dry_run; then
    check_skip "all self-checks (--dry-run)"
    return 0
  fi

  check_unit_active docker
  check_unit_active prometheus-node-exporter
  check_unit_enabled haproxy

  check_unit_active fluentd
  if [ "$SKIP_OBSERVABILITY" = "yes" ]; then
    check_skip "cadvisor / prometheus / loki (--skip-observability)"
  else
    check_unit_active cadvisor
    check_unit_active prometheus
    check_unit_active loki
    check_prometheus_labels
  fi

  if [ "$ENROLLED" = "yes" ]; then
    check_unit_active cs-agent
    check_agent_http
    check_docker_user_rules
  else
    check_skip "cs-agent, its HTTP front door and the DOCKER-USER rules (not enrolled)"
  fi
}

# ===========================================================================
# Closing summary
# ===========================================================================
print_next_steps() {
  cat <<EOF

===========================================================================
Node ${NODE_HOSTNAME} (${VM_IP}), region ${REGION}
===========================================================================

Remaining steps, on the WORKSTATION (not here):

  1. .envrc -- these must match what this node was installed with:

         export DEV_VM_IP=${VM_IP}
         export CONTROLLER_IP=${CONTROLLER_IP}
         export PORTAL_HTTP_SCHEME=http
         export NODE_ENROLLMENT_TOKEN=<the same secret passed to --token>

     SECRET_KEY_BASE must be at least 128 characters -- Secret#crypt_key
     raises below that, and node agent_tokens are encrypted with it, so a
     short value silently nils every token. \`./bin/rails secret\` gives 128.

  2. docker compose up -d          # postgres, redis, powerdns, acme, guacamole
  3. ./bin/rails db:setup
  4. bundle exec rake setup_dev    # creates the Node row this node enrolls against
EOF

  cat <<EOF
  5. DNS is left to you, deliberately. THIS NODE is fine -- it resolves
     ${LB_DOMAIN}, ${REGISTRY_DOMAIN} and
     ${CONTROLLER_DOMAIN} from its own /etc/hosts, written above.
     The WORKSTATION is not: the cstacks.local zone baked into the dev
     PowerDNS image points every record at 127.0.0.1, which was right when
     the node and the controller were one box and is wrong now. If you need
     the controller to reach the registry, or a browser to reach a deployed
     container, map those names to ${VM_IP} yourself -- /etc/hosts for the
     fixed names, or point a resolver at the dev PowerDNS container if you
     want *.${LB_DOMAIN} too. See doc/development.md.

  6. ./bin/dev                     # web, worker, clock

EOF

  if [ "$ENROLLED" != "yes" ]; then
    cat <<EOF
  !! THIS NODE IS NOT ENROLLED. After step 4, come back here and run:

         $0 --enroll-only --controller-ip ${CONTROLLER_IP} \\
             --vm-ip ${VM_IP} --token <the same NODE_ENROLLMENT_TOKEN>

     --token is not optional: ssh does not forward environment variables.
     Until then cs-agent is not running and every Agent::Client call fails.

EOF
  fi

  if [ "$SSH_TRUST_OK" != "yes" ]; then
    cat <<EOF
  !! The controller's SSH public key was NOT installed on this node. Until it
     is, setup_dev, volume management, LB certificate deploys and haproxy
     reloads all fail. On the workstation:

         cat ~/.ssh/computestacks_dev.pub

     copy that file here, then:

         $0 --enroll-only --controller-ip ${CONTROLLER_IP} \\
            --vm-ip ${VM_IP} --ssh-pubkey-file <path to the copied .pub>

EOF
  fi

  cat <<EOF
Reference: the ComputeStacks Ansible provisioner is authoritative for how a
real production node is built. This script is a stripped single-host
derivative of it, last synced 2026-09-12.

EOF
}

# ===========================================================================
# main
# ===========================================================================
main() {
  parse_args "$@"
  step_00_preflight

  if [ "$ENROLL_ONLY" = "yes" ]; then
    log ""
    log "--enroll-only: skipping steps 1-15"
    step_07_ssh_trust
    step_16_enrollment
    step_17_self_checks
    print_next_steps
    if [ "$ENROLLED" != "yes" ]; then
      exit 1
    fi
    [ "$SELF_CHECK_FAILURES" -gt 0 ] && exit 1
    exit 0
  fi

  step_01_base_system
  step_02_reboot_gate
  step_03_kernel
  step_04_docker_engine
  step_05_docker_daemon_json
  step_06_docker_listener
  step_07_ssh_trust
  step_08_haproxy
  step_09_wildcard_cert
  step_10_registry
  step_11_node_exporter
  step_12_preload_images
  step_13_observability
  step_14_firewall
  step_15_cs_agent
  step_16_enrollment
  step_17_self_checks
  print_next_steps

  # A failed self-check on a node that DID enroll is a real failure. A node
  # that has not enrolled yet is the expected first-run state, and the banner
  # above already says so loudly, so that exits 0.
  if [ "$ENROLLED" = "yes" ] && [ "$SELF_CHECK_FAILURES" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

main "$@"
