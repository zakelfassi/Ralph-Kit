#!/bin/bash
set -euo pipefail

# =============================================================================
# Ralph Daemon (Portable)
# =============================================================================
# Periodically runs Ralph planning/build based on REQUESTS.md and IMPLEMENTATION_PLAN.md.
#
# Usage: ./ralph/bin/ralph-daemon.sh [interval_seconds]
# Default interval: 300 (5 minutes)
#
# Triggers (in REQUESTS.md):
#   [PAUSE]   - pause daemon loop
#   [REPLAN]  - run planning once, then continue
#   [DEPLOY]  - run deploy command (RALPH_DEPLOY_CMD), if configured
# =============================================================================

INTERVAL=${1:-300}
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_DIR/ralph/config.sh" 2>/dev/null || true

RUNTIME_DIR="${RALPH_RUNTIME_DIR:-.ralph}"
if [[ "$RUNTIME_DIR" != /* ]]; then
    RUNTIME_DIR="$REPO_DIR/$RUNTIME_DIR"
fi
mkdir -p "$RUNTIME_DIR/logs"

LOG_FILE="${RALPH_DAEMON_LOG_FILE:-$RUNTIME_DIR/logs/daemon.log}"
LOCK_FILE="${RALPH_DAEMON_LOCK_FILE:-$RUNTIME_DIR/daemon.lock}"

REQUESTS_FILE="${RALPH_REQUESTS_FILE:-REQUESTS.md}"
PLAN_FILE="${RALPH_IMPLEMENTATION_PLAN_FILE:-IMPLEMENTATION_PLAN.md}"

notify() {
    if [ -x "$REPO_DIR/ralph/bin/notify.sh" ]; then
        "$REPO_DIR/ralph/bin/notify.sh" "$@" 2>/dev/null || true
    fi
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

is_paused() {
    grep -q '\\[PAUSE\\]' "$REPO_DIR/$REQUESTS_FILE" 2>/dev/null
}

consume_flag() {
    local flag="$1"
    local file="$REPO_DIR/$REQUESTS_FILE"
    grep -q "\\[$flag\\]" "$file" 2>/dev/null || return 1
    # GNU/BSD compatible in-place edit
    sed -i.bak "s/\\[$flag\\]//g" "$file" && rm -f "$file.bak"
    git add "$REQUESTS_FILE" 2>/dev/null || true
    git commit -m "ralph: processed $flag" --allow-empty 2>/dev/null || true
    return 0
}

has_pending_tasks() {
    [ -f "$REPO_DIR/$PLAN_FILE" ] && grep -q '^\\- \\[ \\]' "$REPO_DIR/$PLAN_FILE" 2>/dev/null
}

run_plan() {
    log "Running planning..."
    notify "📋" "Ralph Planning" "Starting plan"
    (cd "$REPO_DIR" && "$REPO_DIR/ralph/bin/loop.sh" plan 1) || true
}

run_build() {
    local iters="${1:-10}"
    log "Running build ($iters iterations)..."
    notify "🔨" "Ralph Build" "Starting build ($iters iterations)"
    (cd "$REPO_DIR" && "$REPO_DIR/ralph/bin/loop.sh" "$iters") || true
}

run_deploy() {
    if [ -z "${RALPH_DEPLOY_CMD:-}" ]; then
        log "DEPLOY requested but RALPH_DEPLOY_CMD not set; skipping"
        notify "⚠️" "Ralph Deploy" "DEPLOY requested but no deploy command configured"
        return 0
    fi

    log "Running deploy: $RALPH_DEPLOY_CMD"
    notify "🚀" "Ralph Deploy" "Running deploy"
    (cd "$REPO_DIR" && bash -lc "$RALPH_DEPLOY_CMD") || true
}

main_loop() {
    log "Ralph daemon starting (interval: ${INTERVAL}s)"

    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log "Another daemon instance is running. Exiting."
        exit 0
    fi

    notify "🤖" "Ralph Daemon Started" "Interval: ${INTERVAL}s"

    while true; do
        if is_paused; then
            log "Paused ([PAUSE] in $REQUESTS_FILE). Sleeping..."
            sleep "$INTERVAL"
            continue
        fi

        if consume_flag "REPLAN"; then
            run_plan
        fi

        if consume_flag "DEPLOY"; then
            run_deploy
        fi

        if [ ! -f "$REPO_DIR/$PLAN_FILE" ]; then
            run_plan
        fi

        if has_pending_tasks; then
            run_build 10
        else
            log "No pending tasks. Sleeping..."
        fi

        sleep "$INTERVAL"
    done
}

trap 'log "Shutting down..."; exit 0' SIGINT SIGTERM
main_loop

