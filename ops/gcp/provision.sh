#!/usr/bin/env bash
set -euo pipefail

# Forgeloop - GCP provisioner
#
# Runs locally (your laptop) and:
# - creates a GCE VM
# - uploads this forgeloop
# - bootstraps the VM with prerequisites + agent CLIs
# - optionally installs API keys for full-auto mode
#
# Requirements:
# - gcloud CLI installed and authenticated

usage() {
  cat <<'USAGE'
Provision a Forgeloop-equipped GCP VM.

Usage:
  ops/gcp/provision.sh [--name NAME] [--zone ZONE] [--machine-type TYPE] [--disk-size SIZE] [--project PROJECT] [--repo-url URL] [--dry-run]

Env (optional):
  OPENAI_API_KEY        OpenAI key for Codex CLI
  ANTHROPIC_API_KEY     Anthropic key for Claude Code

Examples:
  # Minimal (no keys copied)
  ops/gcp/provision.sh --name forgeloop-runner

  # With keys (recommended for full-auto)
  OPENAI_API_KEY=... ANTHROPIC_API_KEY=... ops/gcp/provision.sh --name forgeloop-runner

  # Provision and clone a target repo on the VM
  ops/gcp/provision.sh --name forgeloop-runner --repo-url git@github.com:org/repo.git

Notes:
- API keys are uploaded to the VM and stored at /etc/forgeloop/keys.env (mode 600).
- Prefer a dedicated VM/project with least-privilege keys.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAME="forgeloop-runner"
ZONE="us-central1-a"
MACHINE_TYPE="e2-standard-4"
DISK_SIZE="100GB"
PROJECT=""
REPO_URL=""
DRY_RUN="false"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --name)
      NAME="${2:-}"
      shift 2
      ;;
    --zone)
      ZONE="${2:-}"
      shift 2
      ;;
    --machine-type)
      MACHINE_TYPE="${2:-}"
      shift 2
      ;;
    --disk-size)
      DISK_SIZE="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Error: gcloud not found. Install the Google Cloud SDK." >&2
  exit 1
fi

if [ -z "$PROJECT" ]; then
  PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
fi

if [ -z "$PROJECT" ]; then
  echo "Error: GCP project not set. Pass --project or run: gcloud config set project <id>" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

KIT_TAR="$TMP_DIR/forgeloop.tgz"
SECRETS_FILE="$TMP_DIR/forgeloop-secrets.env"

# Create tarball (exclude .git)
( cd "$KIT_DIR" && tar --exclude='.git' --exclude='.DS_Store' -czf "$KIT_TAR" . )

HAS_KEYS="false"
if [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  HAS_KEYS="true"
  {
    [ -n "${OPENAI_API_KEY:-}" ] && echo "OPENAI_API_KEY=$OPENAI_API_KEY"
    [ -n "${ANTHROPIC_API_KEY:-}" ] && echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
  } > "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
fi

echo "Provisioning VM: $NAME ($PROJECT / $ZONE)"

create_cmd=(
  gcloud compute instances create "$NAME"
  --project "$PROJECT"
  --zone "$ZONE"
  --machine-type "$MACHINE_TYPE"
  --boot-disk-size "$DISK_SIZE"
  --image-family ubuntu-2204-lts
  --image-project ubuntu-os-cloud
)

if [ "$DRY_RUN" = "true" ]; then
  printf 'DRY RUN: %q ' "${create_cmd[@]}"; echo
else
  "${create_cmd[@]}"
fi

# Upload kit tar
scp_cmd=(gcloud compute scp --project "$PROJECT" --zone "$ZONE" "$KIT_TAR" "$NAME:~/forgeloop.tgz")
if [ "$DRY_RUN" = "true" ]; then
  printf 'DRY RUN: %q ' "${scp_cmd[@]}"; echo
else
  "${scp_cmd[@]}"
fi

# Upload secrets (optional)
if [ "$HAS_KEYS" = "true" ]; then
  scp_keys_cmd=(gcloud compute scp --project "$PROJECT" --zone "$ZONE" "$SECRETS_FILE" "$NAME:~/forgeloop-secrets.env")
  if [ "$DRY_RUN" = "true" ]; then
    printf 'DRY RUN: %q ' "${scp_keys_cmd[@]}"; echo
  else
    "${scp_keys_cmd[@]}"
  fi
else
  echo "No API keys provided (OPENAI_API_KEY / ANTHROPIC_API_KEY). Skipping key upload."
fi

# Extract kit to /opt and run bootstrap
remote_bootstrap=$(cat <<'REMOTE'
set -euo pipefail
sudo mkdir -p /opt/forgeloop
sudo tar -xzf "$HOME/forgeloop.tgz" -C /opt/forgeloop
sudo bash /opt/forgeloop/ops/gcp/bootstrap.sh
REMOTE
)

ssh_cmd=(gcloud compute ssh --project "$PROJECT" --zone "$ZONE" "$NAME" --command "$remote_bootstrap")
if [ "$DRY_RUN" = "true" ]; then
  printf 'DRY RUN: %q ' "${ssh_cmd[@]}"; echo
else
  "${ssh_cmd[@]}"
fi

# Optional: clone a target repo and install kit into it
if [ -n "$REPO_URL" ]; then
  remote_repo=$(cat <<REMOTE
set -euo pipefail
mkdir -p "\$HOME/work"
cd "\$HOME/work"
if [ ! -d repo ]; then
  git clone "$REPO_URL" repo
fi
/opt/forgeloop/install.sh "\$HOME/work/repo" --wrapper
REMOTE
)

  ssh_repo_cmd=(gcloud compute ssh --project "$PROJECT" --zone "$ZONE" "$NAME" --command "$remote_repo")
  if [ "$DRY_RUN" = "true" ]; then
    printf 'DRY RUN: %q ' "${ssh_repo_cmd[@]}"; echo
  else
    "${ssh_repo_cmd[@]}"
  fi

  echo "Repo cloned to ~/work/repo on the VM."
  echo "SSH in and run: cd ~/work/repo && ./forgeloop.sh plan 1"
fi

echo "Done. SSH in: gcloud compute ssh $NAME --project $PROJECT --zone $ZONE"
