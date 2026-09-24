#!/usr/bin/env bash
#
# ComputeStacks developer WORKSTATION bootstrap.
#
# Target: a fresh Ubuntu 26.04 "resolute" VM.
#
# This is the machine that will run the controller (Rails) and its supporting
# containers. The container node is a separate VM, bootstrapped by
# lib/dev/single-node.sh.
#
# STANDALONE BY DESIGN. It runs on a vanilla Ubuntu VM *before* the
# repository is cloned, because cloning needs credentials this script has no
# business handling -- GitHub for the public repo, or your own remote if you
# have one. So it installs tools and prepares your account, then PRINTS the
# values you will need, rather than writing into a checkout that does not
# exist yet.
#
# Getting it onto a bare VM: copy it there -- it is a single self-contained
# file with no dependencies beyond the distro.
#
#   scp lib/dev/workstation.sh <you>@<workstation vm>:
#
# (or paste it, or fetch it from wherever your team publishes it).
#
# Usage:
#   sudo bash workstation.sh --user <you> [--node-ip <node vm ip>]
#
# Safe to re-run: nothing is overwritten, and generated secrets are kept.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

TARGET_USER="ubuntu"
NODE_IP=""
SKIP_DOCKER=0
SKIP_MISE=0
DRY_RUN=0

TARGET_HOME=""
TARGET_GROUP=""
DISTRO_CODENAME=""

SSH_KEY_NAME="computestacks_dev"
ENV_HINTS_FILE=""

log()  { printf '[workstation] %s\n' "$*"; }
warn() { printf '[workstation] WARNING: %s\n' "$*" >&2; }
die()  { printf '[workstation] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: workstation.sh [options]

Prepare this machine as a ComputeStacks developer workstation: Docker, mise,
the toolchain build dependencies, an SSH keypair for reaching the node VM, and
a generated set of dev secrets. It does NOT clone the repository -- that is a
manual step, because it needs your credentials.

Options:
  --user <name>     Account to configure (default: ubuntu)
  --node-ip <ip>    The container node VM's address. Optional; only used to
                    fill in the guidance printed at the end.
  --skip-docker     Do not install Docker or touch group membership
  --skip-mise       Do not install mise or the shell hook
  --dry-run         Print what would happen, change nothing
  --help            This text

Targets Ubuntu 26.04 only. Must be run as root (e.g. via sudo), except
with --dry-run.
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --user)     [ $# -ge 2 ] || die "--user requires an argument"; TARGET_USER="$2"; shift 2 ;;
      --user=*)   TARGET_USER="${1#*=}"; shift ;;
      --node-ip)  [ $# -ge 2 ] || die "--node-ip requires an argument"; NODE_IP="$2"; shift 2 ;;
      --node-ip=*) NODE_IP="${1#*=}"; shift ;;
      --skip-docker) SKIP_DOCKER=1; shift ;;
      --skip-mise)   SKIP_MISE=1; shift ;;
      --dry-run)     DRY_RUN=1; shift ;;
      --help|-h)     usage; exit 0 ;;
      *) die "unknown argument: $1 (see --help)" ;;
    esac
  done
}

preflight() {
  if [ "$DRY_RUN" -ne 1 ] && [ "$(id -u)" -ne 0 ]; then
    die "must be run as root (use sudo), or pass --dry-run"
  fi

  id "$TARGET_USER" >/dev/null 2>&1 \
    || die "user '$TARGET_USER' does not exist; create it first, or pass --user <name>"

  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  TARGET_GROUP="$(id -gn "$TARGET_USER")"
  [ -n "$TARGET_HOME" ] || die "could not resolve a home directory for '$TARGET_USER'"
  ENV_HINTS_FILE="${TARGET_HOME}/computestacks-dev.env"

  [ -f /etc/os-release ] || die "cannot detect distro: /etc/os-release not found"
  local distro_id distro_ver
  distro_id="$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
  distro_ver="$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
  DISTRO_CODENAME="$(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '"')"

  # Ubuntu 26.04 only. ComputeStacks development standardises on it, and
  # supporting a second distro would mean shipping an apt path nobody tests.
  if [ "$distro_id" != "ubuntu" ] || [ "$distro_ver" != "26.04" ]; then
    die "this script targets Ubuntu 26.04; found '${distro_id:-unknown} ${distro_ver:-unknown}'"
  fi
  [ -n "$DISTRO_CODENAME" ] || die "could not read VERSION_CODENAME from /etc/os-release"

  log "target user: $TARGET_USER (home: $TARGET_HOME)"
  log "distro: ubuntu ${distro_ver} (${DISTRO_CODENAME})"
  [ "$DRY_RUN" -eq 1 ] && log "--dry-run: nothing will be changed"
  return 0
}

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------
#
# tmux      - overmind (a gem, from the bundle) shells out to it; ./bin/dev
#             does not work without it.
# just      - `just build` builds the production image locally.
# libpq-dev - the `pg` gem compiles against it; `bundle install` fails otherwise.
# The rest are ruby-build's prerequisites: mise compiles Ruby from source, so
# `mise install` dies without them.
BASE_PACKAGES=(
  ca-certificates curl gnupg git tmux just
  build-essential autoconf patch pkg-config
  libpq-dev libssl-dev libyaml-dev libreadline-dev zlib1g-dev
  libgmp-dev libncurses-dev libffi-dev libgdbm-dev uuid-dev
)

install_base_packages() {
  log "installing base packages and toolchain build dependencies"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] apt-get install: ${BASE_PACKAGES[*]}"
    return 0
  fi
  apt-get update
  apt-get install -y "${BASE_PACKAGES[@]}"
}

install_docker() {
  if [ "$SKIP_DOCKER" -eq 1 ]; then
    log "skipping Docker (--skip-docker)"
    return 0
  fi

  log "installing Docker CE from Docker's official Ubuntu repo ($DISTRO_CODENAME)"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] add Docker's apt repo and install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
  else
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
      "$(dpkg --print-architecture)" "$DISTRO_CODENAME" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] add $TARGET_USER to the docker group if needed"
  elif id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
    log "$TARGET_USER is already in the docker group"
  else
    usermod -aG docker "$TARGET_USER"
    log "added $TARGET_USER to the docker group"
  fi
}

# ---------------------------------------------------------------------------
# mise
# ---------------------------------------------------------------------------
user_shell_is_zsh() {
  case "$(getent passwd "$TARGET_USER" | cut -d: -f7)" in
    */zsh) return 0 ;;
    *) return 1 ;;
  esac
}

install_mise() {
  if [ "$SKIP_MISE" -eq 1 ]; then
    log "skipping mise (--skip-mise)"
    return 0
  fi

  local mise_bin="${TARGET_HOME}/.local/bin/mise"

  if [ -x "$mise_bin" ]; then
    log "mise already installed at $mise_bin"
  elif [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] install mise to $mise_bin as $TARGET_USER"
  else
    runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" bash -c "curl -fsSL https://mise.run | sh"
    [ -x "$mise_bin" ] || die "mise install did not produce $mise_bin"
    log "installed mise to $mise_bin"
  fi

  local rc_file activate_line
  # shellcheck disable=SC2016  # deliberate: this line is written verbatim into
  # the rc file and must be expanded by the user's shell at login, not here.
  if user_shell_is_zsh; then
    rc_file="${TARGET_HOME}/.zshrc"; activate_line='eval "$(mise activate zsh)"'
  else
    rc_file="${TARGET_HOME}/.bashrc"; activate_line='eval "$(mise activate bash)"'
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] ensure '$activate_line' is in $rc_file"
    return 0
  fi

  touch "$rc_file"
  chown "${TARGET_USER}:${TARGET_GROUP}" "$rc_file"
  if grep -qxF "$activate_line" "$rc_file"; then
    log "$rc_file already activates mise"
  else
    printf '%s\n' "$activate_line" >>"$rc_file"
    log "added mise activation to $rc_file"
  fi

  # The toolchain itself is deliberately NOT installed here: the versions come
  # from the repository's .tool-versions, which does not exist yet. `mise
  # install` after cloning does it.
}

# ---------------------------------------------------------------------------
# SSH keypair
# ---------------------------------------------------------------------------
#
# Lives in ~/.ssh rather than the repo's lib/dev/keys/ so that it survives
# re-cloning and exists before the clone. CS_SSH_KEY accepts an absolute path
# (setup_dev builds it with Rails.root.join, and an absolute argument wins).
generate_ssh_key() {
  local key="${TARGET_HOME}/.ssh/${SSH_KEY_NAME}"

  if [ -f "$key" ]; then
    log "SSH key already present at $key"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] generate an ed25519 keypair at $key"
    return 0
  fi

  install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_GROUP" "${TARGET_HOME}/.ssh"
  ssh-keygen -t ed25519 -N '' -f "$key" -C "computestacks-dev-${TARGET_USER}" >/dev/null
  chown "${TARGET_USER}:${TARGET_GROUP}" "$key" "${key}.pub"
  chmod 0600 "$key"
  chmod 0644 "${key}.pub"
  log "generated $key"
}

# ---------------------------------------------------------------------------
# Secrets and the .envrc hint file
# ---------------------------------------------------------------------------
#
# Written to a file as well as printed: a developer who scrolls past the
# output should not have to re-run anything to get their secrets back, and
# regenerating SECRET_KEY_BASE later would invalidate every stored node token.
write_env_hints() {
  if [ -f "$ENV_HINTS_FILE" ]; then
    log "keeping existing $ENV_HINTS_FILE (secrets already generated)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] generate secrets into $ENV_HINTS_FILE"
    return 0
  fi

  local controller_ip
  controller_ip="$(ip -4 -o addr show scope global 2>/dev/null \
    | awk '{print $4}' | cut -d/ -f1 | head -n1)"

  {
    echo "# Generated by workstation.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)."
    echo "# Merge these into .envrc AFTER cloning the repository."
    echo "#"
    echo "# SECRET_KEY_BASE must stay >= 128 characters: Secret#crypt_key raises"
    echo "# below that, and node agent_tokens are encrypted with it, so a short"
    echo "# value silently nils every token instead of erroring."
    echo "export SECRET_KEY_BASE=$(openssl rand -hex 64)"
    echo "export USER_AUTH_SECRET=$(openssl rand -hex 64)"
    echo "# Must match the --token passed to single-node.sh on the node VM."
    echo "export NODE_ENROLLMENT_TOKEN=$(openssl rand -hex 64)"
    echo ""
    echo "# The container node VM."
    echo "export DEV_VM_IP=${NODE_IP:-<node vm ip>}"
    echo "# This workstation, as the node sees it. Normally autodetected; set it"
    echo "# only if the wrong interface is chosen."
    echo "# export CONTROLLER_IP=${controller_ip:-<this workstation ip>}"
    echo ""
    echo "# The dev Procfile serves plain HTTP on :3005. Production defaults to"
    echo "# https, which would make the load balancer config push fail here."
    echo "export PORTAL_HTTP_SCHEME=http"
    echo ""
    echo "# Absolute path: this key lives outside the checkout so it survives a"
    echo "# re-clone."
    echo "export CS_SSH_KEY=${TARGET_HOME}/.ssh/${SSH_KEY_NAME}"
  } >"$ENV_HINTS_FILE"

  chown "${TARGET_USER}:${TARGET_GROUP}" "$ENV_HINTS_FILE"
  chmod 0600 "$ENV_HINTS_FILE"
  log "wrote $ENV_HINTS_FILE (mode 0600)"
}

print_next_steps() {
  local pub="${TARGET_HOME}/.ssh/${SSH_KEY_NAME}.pub"
  local node_display="${NODE_IP:-<node vm ip>}"

  echo
  echo "==========================================================================="
  echo " Workstation ready for '${TARGET_USER}'."
  echo "==========================================================================="
  echo
  if [ "$SKIP_DOCKER" -ne 1 ]; then
    echo " FIRST: log out and back in (or run 'newgrp docker') before using docker."
    echo " Group membership does not apply to your current session."
    echo
  fi
  echo " 1. Install the container node, if you have not already. On the NODE VM,"
  echo "    as root, with this workstation's public key:"
  echo
  if [ -f "$pub" ]; then
    echo "      $(cat "$pub")"
  else
    echo "      (public key at ${pub})"
  fi
  echo
  echo "    See lib/dev/single-node.sh --help. Its --token must match the"
  echo "    NODE_ENROLLMENT_TOKEN below."
  echo
  echo " 2. Clone the repository. This script deliberately does not, so that"
  echo "    your credentials stay yours:"
  echo
  echo "      git clone https://github.com/ComputeStacks/controller.git"
  echo "      cd controller"
  echo
  echo " 3. Set up the environment:"
  echo
  echo "      cp envrc.sample .envrc"
  echo "      # then merge in the generated values from:"
  echo "      #   ${ENV_HINTS_FILE}"
  echo "      cp config/database.sample.yml config/database.yml"
  echo "      mise trust && mise install    # .mise.toml loads .envrc; mise, not direnv"
  echo
  echo " 4. Bring it up:"
  echo
  echo "      docker compose up -d"
  echo "      bundle install"
  echo "      ./bin/rails db:setup"
  echo "      bundle exec rake setup_dev    # creates the Node row for ${node_display}"
  echo "      ./bin/dev                     # web, worker, clock on :3005"
  echo
  echo " 5. Back on the node VM, enroll it:"
  echo
  echo "      single-node.sh --enroll-only --controller-ip <this workstation> \\"
  echo "        --vm-ip ${node_display} --token <NODE_ENROLLMENT_TOKEN>"
  echo
  echo " Full walkthrough: doc/development.md in the repository."
  echo
  if [ "$DRY_RUN" -eq 1 ]; then
    echo " (--dry-run: nothing above was actually done.)"
    echo
  fi
}

main() {
  parse_args "$@"
  preflight
  install_base_packages
  install_docker
  install_mise
  generate_ssh_key
  write_env_hints
  print_next_steps
}

main "$@"
