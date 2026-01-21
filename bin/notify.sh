#!/bin/bash
# Manual notification script (Slack Incoming Webhook)
# Usage: ./ralph/bin/notify.sh "emoji" "title" "message"

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_DIR/.env.local" 2>/dev/null || true

if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
    echo "Error: SLACK_WEBHOOK_URL not set"
    echo "Create .env.local with: SLACK_WEBHOOK_URL=your-webhook-url"
    exit 1
fi

emoji="${1:-📢}"
title="${2:-Notification}"
message="${3:-No message provided}"
host=$(hostname)
ts=$(date '+%Y-%m-%d %H:%M:%S')

text="$emoji *$title*\n$message\n_${host} • ${ts}_"

curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H 'Content-type: application/json' \
    -d "{\"text\":\"$text\"}"

echo ""
echo "Notification sent!"

