#!/usr/bin/env bash
set -euo pipefail

# Forgeloop - GCP VM bootstrap
#
# Intended to run on an Ubuntu VM (as root via sudo).
# Installs:
# - base tools: git/curl/jq/tmux
# - Node.js + pnpm
# - codex + claude CLIs (best-effort)
# - optional API key env file at /etc/forgeloop/keys.env
# - optional /opt/forgeloop (if a tarball was provided separately)
#
# Usage:
#   sudo bash bootstrap.sh

log() {
  echo "[bootstrap] $1"
}

SUDO_USER_NAME="${SUDO_USER:-}"
if [ -z "$SUDO_USER_NAME" ]; then
  SUDO_USER_NAME="$(whoami)"
fi

USER_HOME="/home/$SUDO_USER_NAME"

# Inputs (expected to exist if provision script uploaded them)
SECRETS_FILE_DEFAULT="$USER_HOME/forgeloop-secrets.env"

SECRETS_FILE="$SECRETS_FILE_DEFAULT"
SKIP_CODEX="false"
SKIP_CLAUDE="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --secrets-file)
      SECRETS_FILE="${2:-}"
      shift 2
      ;;
    --skip-codex)
      SKIP_CODEX="true"
      shift
      ;;
    --skip-claude)
      SKIP_CLAUDE="true"
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  sudo bash bootstrap.sh [--secrets-file /path/to/env] [--skip-codex] [--skip-claude]

Notes:
- If --secrets-file exists, it will be installed to /etc/forgeloop/keys.env (mode 600).
- Secrets file should contain lines like OPENAI_API_KEY=... and/or ANTHROPIC_API_KEY=...
USAGE
      exit 0
      ;;
    *)
      log "Unknown arg: $1"
      exit 1
      ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  log "Error: run as root (use sudo)"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log "Updating apt + installing base packages..."
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  jq \
  tmux \
  unzip \
  gettext-base \
  build-essential

log "Installing Node.js (NodeSource 22.x)..."
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

log "Enabling pnpm (via Corepack)..."
if command -v corepack >/dev/null 2>&1; then
  corepack enable || true
  corepack prepare pnpm@latest --activate || true
else
  log "corepack not found; installing pnpm via npm"
  npm install -g pnpm
fi

log "Installing agent CLIs (best-effort)..."
if [ "$SKIP_CODEX" != "true" ]; then
  if ! command -v codex >/dev/null 2>&1; then
    npm install -g @openai/codex || log "codex install failed (you may need to install manually)"
  fi
fi

if [ "$SKIP_CLAUDE" != "true" ]; then
  if ! command -v claude >/dev/null 2>&1; then
    npm install -g @anthropic-ai/claude-code || log "claude install failed (you may need to install manually)"
  fi
fi

log "Configuring optional API keys..."
mkdir -p /etc/forgeloop

if [ -f "$SECRETS_FILE" ]; then
  install -m 600 -o root -g root "$SECRETS_FILE" /etc/forgeloop/keys.env
  log "Installed secrets to /etc/forgeloop/keys.env"
else
  log "No secrets file found at $SECRETS_FILE (skipping key install)"
fi

cat > /etc/profile.d/forgeloop-env.sh <<'PROFILE'
# Forgeloop env loader (API keys)
# - Loads /etc/forgeloop/keys.env if present
# - keys.env should contain VAR=VALUE lines

if [ -f /etc/forgeloop/keys.env ]; then
  set -a
  . /etc/forgeloop/keys.env
  set +a
fi
PROFILE
chmod 644 /etc/profile.d/forgeloop-env.sh

log "Bootstrap complete."
log "Next steps (as $SUDO_USER_NAME):"
log "  - source /etc/profile.d/forgeloop-env.sh (or reconnect SSH)"
log "  - clone your target repo"
log "  - install kit into repo: /opt/forgeloop/install.sh /path/to/repo --wrapper"
log "  - run: ./forgeloop.sh plan 1 && ./forgeloop.sh build 10"
