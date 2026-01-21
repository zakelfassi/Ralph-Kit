#!/bin/bash
set -euo pipefail

# =============================================================================
# Ralph Loop (Portable)
# =============================================================================
# Runs an agent loop using Claude and/or Codex CLIs with task-based routing.
#
# Usage:
#   ./ralph/bin/loop.sh [plan] [max_iterations]
#   ./ralph/bin/loop.sh plan-work "work description" [max_iterations]
#   ./ralph/bin/loop.sh review
#   ./ralph/bin/loop.sh [max_iterations]
#
# Config:
#   See `ralph/config.sh` (autopush off by default).
# =============================================================================

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_DIR/ralph/config.sh" 2>/dev/null || true

RUNTIME_DIR="${RALPH_RUNTIME_DIR:-.ralph}"
if [[ "$RUNTIME_DIR" != /* ]]; then
    RUNTIME_DIR="$REPO_DIR/$RUNTIME_DIR"
fi
mkdir -p "$RUNTIME_DIR/logs"

LOG_FILE="${RALPH_LOOP_LOG_FILE:-$RUNTIME_DIR/logs/loop.log}"
STATE_FILE="$RUNTIME_DIR/state"

REVIEW_SCHEMA="${RALPH_REVIEW_SCHEMA:-$REPO_DIR/ralph/schemas/review.schema.json}"
SECURITY_SCHEMA="${RALPH_SECURITY_SCHEMA:-$REPO_DIR/ralph/schemas/security.schema.json}"

PROMPT_PLAN="${RALPH_PROMPT_PLAN:-PROMPT_plan.md}"
PROMPT_BUILD="${RALPH_PROMPT_BUILD:-PROMPT_build.md}"
PROMPT_PLAN_WORK="${RALPH_PROMPT_PLAN_WORK:-PROMPT_plan_work.md}"

notify() {
    if [ -x "$REPO_DIR/ralph/bin/notify.sh" ]; then
        "$REPO_DIR/ralph/bin/notify.sh" "$@" 2>/dev/null || true
    fi
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

save_state() {
    cat > "$STATE_FILE" << EOF
AI_MODEL=$AI_MODEL
CLAUDE_RATE_LIMITED_UNTIL=$CLAUDE_RATE_LIMITED_UNTIL
CODEX_RATE_LIMITED_UNTIL=$CODEX_RATE_LIMITED_UNTIL
EOF
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
        if [ -n "${FORCE_MODEL:-}" ]; then
            AI_MODEL="$FORCE_MODEL"
        fi
        log "Loaded state: model=$AI_MODEL, claude_limit=$CLAUDE_RATE_LIMITED_UNTIL, codex_limit=$CODEX_RATE_LIMITED_UNTIL"
    fi
}

has_claude() { command -v claude &> /dev/null; }
has_codex() { command -v codex &> /dev/null; }

is_rate_limited() {
    local model="$1"
    local now
    now=$(date +%s)

    case "$model" in
        claude) [ "$CLAUDE_RATE_LIMITED_UNTIL" -gt "$now" ] ;;
        codex) [ "$CODEX_RATE_LIMITED_UNTIL" -gt "$now" ] ;;
        *) return 1 ;;
    esac
}

# =============================================================================
# Model Configuration
# =============================================================================

PLANNING_MODEL="${PLANNING_MODEL:-codex}"
REVIEW_MODEL="${REVIEW_MODEL:-codex}"
SECURITY_MODEL="${SECURITY_MODEL:-codex}"
BUILD_MODEL="${BUILD_MODEL:-claude}"

CLAUDE_CLI="${CLAUDE_CLI:-claude}"
CLAUDE_MODEL="${CLAUDE_MODEL:-opus}"
CLAUDE_FLAGS="${CLAUDE_FLAGS:---dangerously-skip-permissions --output-format=stream-json --verbose}"

CODEX_CLI="${CODEX_CLI:-codex}"
CODEX_FLAGS="${CODEX_FLAGS:---full-auto --sandbox danger-full-access}"

CODEX_PLANNING_CONFIG="${CODEX_PLANNING_CONFIG:-gpt-5.2:high}"
CODEX_REVIEW_CONFIG="${CODEX_REVIEW_CONFIG:-gpt-5.2-codex:medium}"
CODEX_SECURITY_CONFIG="${CODEX_SECURITY_CONFIG:-gpt-5.2-codex:medium}"

ENABLE_FAILOVER="${ENABLE_FAILOVER:-true}"
ENABLE_CODEX_REVIEW="${ENABLE_CODEX_REVIEW:-true}"
TASK_ROUTING="${TASK_ROUTING:-true}"
FORCE_MODEL="${AI_MODEL:-}"
AI_MODEL="${FORCE_MODEL:-$BUILD_MODEL}"

CLAUDE_RATE_LIMITED_UNTIL=0
CODEX_RATE_LIMITED_UNTIL=0

get_model_for_task() {
    local task_type="${1:-build}"

    if [ -n "$FORCE_MODEL" ]; then
        echo "$FORCE_MODEL"
        return 0
    fi

    if [ "$TASK_ROUTING" = "true" ]; then
        case "$task_type" in
            plan|plan-work) echo "$PLANNING_MODEL" ;;
            review) echo "$REVIEW_MODEL" ;;
            security) echo "$SECURITY_MODEL" ;;
            *) echo "$BUILD_MODEL" ;;
        esac
    else
        echo "claude"
    fi
}

get_codex_config_for_task() {
    local task_type="${1:-build}"
    local config=""

    case "$task_type" in
        plan|plan-work) config="$CODEX_PLANNING_CONFIG" ;;
        review) config="$CODEX_REVIEW_CONFIG" ;;
        security) config="$CODEX_SECURITY_CONFIG" ;;
        *) config="$CODEX_PLANNING_CONFIG" ;;
    esac

    local model="${config%%:*}"
    local reasoning="${config##*:}"
    echo "$model $reasoning"
}

parse_rate_limit_duration() {
    local output_file="$1"
    local model="$2"
    local default_sleep=$((60 * 60))

    local reset_time
    reset_time=$(grep -oE "resets [0-9]+[ap]m" "$output_file" 2>/dev/null | head -1 || echo "")

    if [ -n "$reset_time" ]; then
        local hour
        local ampm
        hour=$(echo "$reset_time" | grep -oE "[0-9]+")
        ampm=$(echo "$reset_time" | grep -oE "[ap]m")

        if [ "$ampm" = "pm" ] && [ "$hour" -ne 12 ]; then
            hour=$((hour + 12))
        elif [ "$ampm" = "am" ] && [ "$hour" -eq 12 ]; then
            hour=0
        fi

        local now
        local target
        now=$(TZ="America/Los_Angeles" date +%s)
        target=$(TZ="America/Los_Angeles" date -d "today ${hour}:00" +%s 2>/dev/null || \
                 TZ="America/Los_Angeles" date -j -f "%H:%M" "${hour}:00" +%s 2>/dev/null || echo "")

        if [ -n "$target" ]; then
            local diff=$((target - now))
            if [ "$diff" -lt 0 ]; then
                diff=$((diff + 86400))
            fi
            echo $((diff + 300))
            return
        fi
    fi

    case "$model" in
        claude) echo $((5 * 3600 + 300)) ;;
        codex) echo $((60 * 60)) ;;
        *) echo "$default_sleep" ;;
    esac
}

ai_exec() {
    local prompt_source="$1"  # "file:PATH" or "stdin" or literal prompt
    local task_type="${2:-build}"
    local preferred_model
    preferred_model=$(get_model_for_task "$task_type")
    local model="$preferred_model"
    local output_file
    output_file=$(mktemp)
    local exit_code=0
    local prompt_content=""

    if is_rate_limited "$model" && [ "$ENABLE_FAILOVER" = "true" ]; then
        local alt_model
        if [ "$model" = "claude" ]; then alt_model="codex"; else alt_model="claude"; fi
        if ! is_rate_limited "$alt_model"; then
            log "Preferred model ($model) rate-limited for $task_type, using $alt_model"
            model="$alt_model"
        fi
    fi

    AI_MODEL="$model"

    if [[ "$prompt_source" == file:* ]]; then
        local file_path="${prompt_source#file:}"
        if [ "$MODE" = "plan-work" ] && [ -n "${WORK_SCOPE:-}" ]; then
            prompt_content=$(WORK_SCOPE="$WORK_SCOPE" envsubst < "$file_path")
        else
            prompt_content=$(cat "$file_path")
        fi
    elif [ "$prompt_source" = "stdin" ]; then
        prompt_content=$(cat)
    else
        prompt_content="$prompt_source"
    fi

    log "Executing task=$task_type with model=$model (preferred=$preferred_model)"

    case "$model" in
        claude)
            if ! has_claude; then
                if has_codex; then
                    log "Claude not available, forcing Codex..."
                    FORCE_MODEL="codex" ai_exec "stdin" "$task_type" <<< "$prompt_content"
                    return $?
                fi
                log "Neither Claude nor Codex is available"
                return 127
            fi

            echo "$prompt_content" | $CLAUDE_CLI -p \
                $CLAUDE_FLAGS \
                --model "$CLAUDE_MODEL" \
                2>&1 | tee "$output_file" || exit_code=$?

            if [ "$exit_code" -ne 0 ] && grep -qE "(\"error\":\\{\"type\":\"rate_limit|anthropic.*rate.*limit|Usage limit reached|You.ve run out of|credit balance is too low)" "$output_file" 2>/dev/null; then
                log "Claude rate limited!"
                local sleep_duration
                sleep_duration=$(parse_rate_limit_duration "$output_file" "claude")
                CLAUDE_RATE_LIMITED_UNTIL=$(($(date +%s) + sleep_duration))
                save_state

                if [ "$ENABLE_FAILOVER" = "true" ] && has_codex && ! is_rate_limited "codex"; then
                    log "Failing over to Codex..."
                    notify "🔄" "Model Failover" "Claude rate limited. Switching to Codex."
                    rm -f "$output_file"
                    FORCE_MODEL="codex" ai_exec "stdin" "$task_type" <<< "$prompt_content"
                    return $?
                fi

                local sleep_hours=$((sleep_duration / 3600))
                local sleep_mins=$(((sleep_duration % 3600) / 60))
                log "Sleeping ${sleep_hours}h ${sleep_mins}m..."
                notify "⏸️" "Ralph Paused" "Rate limited. Sleeping ${sleep_hours}h ${sleep_mins}m"
                rm -f "$output_file"
                sleep "$sleep_duration"
                CLAUDE_RATE_LIMITED_UNTIL=0
                save_state
                echo "$prompt_content" | ai_exec "stdin" "$task_type"
                return $?
            fi
            ;;

        codex)
            if ! has_codex; then
                if has_claude; then
                    log "Codex not available, forcing Claude..."
                    FORCE_MODEL="claude" ai_exec "stdin" "$task_type" <<< "$prompt_content"
                    return $?
                fi
                log "Neither Codex nor Claude is available"
                return 127
            fi

            local codex_config
            codex_config=$(get_codex_config_for_task "$task_type")
            local codex_model="${codex_config%% *}"
            local codex_reasoning="${codex_config##* }"

            log "Codex config: model=$codex_model reasoning=$codex_reasoning"

            echo "$prompt_content" | $CODEX_CLI exec \
                $CODEX_FLAGS \
                -m "$codex_model" \
                -c "model_reasoning_effort=\"$codex_reasoning\"" \
                - 2>&1 | tee "$output_file" || exit_code=$?

            if [ "$exit_code" -ne 0 ] && grep -qE "(openai.*rate.*limit|Rate limit reached for|You exceeded your current quota|Request too large)" "$output_file" 2>/dev/null; then
                log "Codex rate limited!"
                local sleep_duration
                sleep_duration=$(parse_rate_limit_duration "$output_file" "codex")
                CODEX_RATE_LIMITED_UNTIL=$(($(date +%s) + sleep_duration))
                save_state

                if [ "$ENABLE_FAILOVER" = "true" ] && has_claude && ! is_rate_limited "claude"; then
                    log "Failing over to Claude..."
                    notify "🔄" "Model Failover" "Codex rate limited. Switching to Claude."
                    rm -f "$output_file"
                    FORCE_MODEL="claude" ai_exec "stdin" "$task_type" <<< "$prompt_content"
                    return $?
                fi

                local sleep_hours=$((sleep_duration / 3600))
                local sleep_mins=$(((sleep_duration % 3600) / 60))
                log "Sleeping ${sleep_hours}h ${sleep_mins}m..."
                notify "⏸️" "Ralph Paused" "Rate limited. Sleeping ${sleep_hours}h ${sleep_mins}m"
                rm -f "$output_file"
                sleep "$sleep_duration"
                CODEX_RATE_LIMITED_UNTIL=0
                save_state
                echo "$prompt_content" | ai_exec "stdin" "$task_type"
                return $?
            fi
            ;;
    esac

    rm -f "$output_file"
    return $exit_code
}

run_codex_review() {
    if ! has_codex || [ "$ENABLE_CODEX_REVIEW" != "true" ]; then
        return 0
    fi
    if is_rate_limited "codex"; then
        log "Skipping Codex review (rate limited)"
        return 0
    fi

    local diff
    diff=$(git diff HEAD~1 2>/dev/null || echo "")
    if [ -z "$diff" ]; then
        log "No changes to review"
        return 0
    fi

    log "Running Codex review..."

    local review_result
    review_result=$(mktemp)

    local codex_config
    codex_config=$(get_codex_config_for_task "review")
    local codex_model="${codex_config%% *}"
    local codex_reasoning="${codex_config##* }"

    {
        printf "Review this diff for bugs, security issues, edge cases, and code quality. Be thorough but concise.\\n"
        printf "Return JSON matching the provided schema.\\n\\nDIFF:\\n"
        printf '%s\\n' "$diff"
    } | $CODEX_CLI exec --sandbox read-only \
        -m "$codex_model" \
        -c "model_reasoning_effort=\\\"$codex_reasoning\\\"" \
        --output-schema "$REVIEW_SCHEMA" \
        -o "$review_result" \
        - 2>&1 || true

    if [ -f "$review_result" ] && [ -s "$review_result" ]; then
        local verdict
        local finding_count
        verdict=$(jq -r '.verdict // "unknown"' "$review_result" 2>/dev/null || echo "unknown")
        finding_count=$(jq -r '.findings | length' "$review_result" 2>/dev/null || echo "0")

        log "Codex review: $verdict ($finding_count findings)"

        if [ "$verdict" = "needs_fixes" ] && [ "$finding_count" -gt 0 ]; then
            local fixes
            fixes=$(jq -r '.findings[] | select(.severity == "high" or .severity == "critical") | "- [\\(.severity)] \\(.title): \\(.fix // .description)"' "$review_result" 2>/dev/null || echo "")

            if [ -n "$fixes" ]; then
                log "Feeding Codex findings back for repair..."
                printf "Fix these issues found in code review:\\n\\n%s" "$fixes" | ai_exec "stdin"

                if [ -n "${RALPH_TEST_CMD:-}" ]; then
                    log "Running tests after review fixes: $RALPH_TEST_CMD"
                    (cd "$REPO_DIR" && bash -lc "$RALPH_TEST_CMD" 2>&1 | tail -50) || true
                fi
            fi
        fi
    fi

    rm -f "$review_result"
}

security_gate() {
    local diff
    diff=$(git diff --staged 2>/dev/null || echo "")
    if [ -z "$diff" ]; then
        diff=$(git diff HEAD~1 2>/dev/null || echo "")
    fi
    [ -z "$diff" ] && return 0

    log "Running security review..."

    local security_result
    security_result=$(mktemp)

    local sec_model
    sec_model=$(get_model_for_task "security")

    if is_rate_limited "$sec_model"; then
        local alt_model
        if [ "$sec_model" = "claude" ]; then alt_model="codex"; else alt_model="claude"; fi
        if ! is_rate_limited "$alt_model"; then
            sec_model="$alt_model"
        else
            log "Both models rate-limited, skipping security review"
            return 0
        fi
    fi

    case "$sec_model" in
        codex)
            local codex_config
            codex_config=$(get_codex_config_for_task "security")
            local codex_model="${codex_config%% *}"
            local codex_reasoning="${codex_config##* }"

            {
                printf "You are a security engineer. Review this diff for vulnerabilities: injection, XSS, auth bypass, secrets exposure, path traversal.\\n"
                printf "Output JSON matching the provided schema.\\n\\nDIFF:\\n"
                printf '%s\\n' "$diff"
            } | $CODEX_CLI exec --sandbox read-only \
                -m "$codex_model" \
                -c "model_reasoning_effort=\\\"$codex_reasoning\\\"" \
                --output-schema "$SECURITY_SCHEMA" \
                -o "$security_result" \
                - 2>&1 || true
            ;;
        claude)
            echo "$diff" | $CLAUDE_CLI -p --output-format json \
                --model "$CLAUDE_MODEL" \
                --append-system-prompt "You are a security engineer. Review for vulnerabilities including: injection, XSS, auth bypass, secrets exposure, path traversal." \
                --json-schema "$(cat "$SECURITY_SCHEMA")" \
                "Review this diff for security vulnerabilities." 2>/dev/null \
            | jq -r '.structured_output // .' > "$security_result" || true
            ;;
    esac

    if [ -f "$security_result" ] && [ -s "$security_result" ]; then
        local safe
        safe=$(jq -r '.safe // true' "$security_result" 2>/dev/null || echo "true")
        if [ "$safe" = "false" ]; then
            log "Security review found issues"
            jq -r '.issues[] | "  - [\\(.severity)] \\(.type): \\(.description)"' "$security_result" 2>/dev/null || true
            notify "🚨" "Security Review Warning" "Found potential security issues in diff"
        fi
    fi

    rm -f "$security_result"
}

is_git_worktree_clean() {
    git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]
}

sync_branch_from_origin() {
    local branch="$1"

    local remote="${RALPH_GIT_REMOTE:-origin}"
    if ! git remote get-url "$remote" >/dev/null 2>&1; then
        return 0
    fi

    if ! is_git_worktree_clean; then
        log "Working tree dirty; skipping sync with $remote/$branch"
        return 0
    fi

    if ! git fetch "$remote" "$branch" 2>/dev/null && ! git fetch "$remote" 2>/dev/null; then
        log "git fetch failed; skipping sync"
        return 0
    fi

    local remote_ref="$remote/$branch"
    if ! git show-ref --verify --quiet "refs/remotes/$remote_ref"; then
        return 0
    fi

    local local_sha remote_sha base_sha
    local_sha=$(git rev-parse "$branch" 2>/dev/null || echo "")
    remote_sha=$(git rev-parse "$remote_ref" 2>/dev/null || echo "")
    [ -z "$local_sha" ] && return 0
    [ -z "$remote_sha" ] && return 0
    [ "$local_sha" = "$remote_sha" ] && return 0

    base_sha=$(git merge-base "$branch" "$remote_ref" 2>/dev/null || echo "")
    [ -z "$base_sha" ] && return 0

    if [ "$local_sha" = "$base_sha" ]; then
        log "Fast-forwarding $branch to $remote_ref"
        git merge --ff-only "$remote_ref" 2>/dev/null || {
            log "Fast-forward failed; manual intervention required"
            return 1
        }
        return 0
    fi

    if [ "$remote_sha" = "$base_sha" ]; then
        return 0
    fi

    if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
        log "Branch $branch diverged from $remote_ref; merging"
        git merge --no-edit "$remote_ref" 2>/dev/null || return 1
        return 0
    fi

    log "Branch $branch diverged from $remote_ref; rebasing local commits"
    if ! git rebase "$remote_ref" 2>/dev/null; then
        log "Rebase failed; aborting and attempting merge"
        git rebase --abort 2>/dev/null || true
        git merge --no-edit "$remote_ref" 2>/dev/null || return 1
    fi
}

push_branch() {
    local branch="$1"

    if [ "${RALPH_AUTOPUSH:-false}" != "true" ]; then
        log "Autopush disabled; skipping push"
        return 0
    fi

    local remote="${RALPH_GIT_REMOTE:-origin}"
    if ! git remote get-url "$remote" >/dev/null 2>&1; then
        log "No git remote '$remote' configured; skipping push"
        return 0
    fi

    if git push "$remote" "$branch" 2>/dev/null; then
        return 0
    fi

    log "Push failed for $branch; syncing with $remote and retrying..."
    if ! sync_branch_from_origin "$branch"; then
        notify "🚨" "Ralph Push Failed" "Failed to sync with $remote/$branch. Manual intervention required."
        return 1
    fi

    git push "$remote" "$branch" 2>/dev/null || {
        notify "🚨" "Ralph Push Failed" "Failed to push $branch after sync. Manual intervention required."
        return 1
    }
}

# =============================================================================
# Arg parsing
# =============================================================================

MODE="build"
PROMPT_FILE="$PROMPT_BUILD"
MAX_ITERATIONS=0

if [ "${1:-}" = "plan" ]; then
    MODE="plan"
    PROMPT_FILE="$PROMPT_PLAN"
    MAX_ITERATIONS=${2:-0}
elif [ "${1:-}" = "plan-work" ]; then
    if [ -z "${2:-}" ]; then
        echo "Error: plan-work requires a work description"
        echo "Usage: ./ralph/bin/loop.sh plan-work \"description\" [max_iterations]"
        exit 1
    fi
    MODE="plan-work"
    WORK_DESCRIPTION="$2"
    PROMPT_FILE="$PROMPT_PLAN_WORK"
    MAX_ITERATIONS=${3:-5}
elif [ "${1:-}" = "review" ]; then
    MODE="review"
    MAX_ITERATIONS=1
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    MAX_ITERATIONS=$1
fi

ITERATION=0
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

if [ "$MODE" = "plan-work" ]; then
    if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
        echo "Error: plan-work should be run on a work branch, not main/master"
        exit 1
    fi
    export WORK_SCOPE="$WORK_DESCRIPTION"
fi

cd "$REPO_DIR"
load_state

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Mode:       $MODE"
echo "Branch:     $CURRENT_BRANCH"
echo "Prompt:     $PROMPT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Task Routing: $TASK_ROUTING"
echo "  Planning: $PLANNING_MODEL ($CODEX_PLANNING_CONFIG)"
echo "  Review:   $REVIEW_MODEL ($CODEX_REVIEW_CONFIG)"
echo "  Security: $SECURITY_MODEL ($CODEX_SECURITY_CONFIG)"
echo "  Build:    $BUILD_MODEL (Claude $CLAUDE_MODEL)"
echo "Failover:   $ENABLE_FAILOVER"
echo "Autopush:   ${RALPH_AUTOPUSH:-false}"
[ "$MAX_ITERATIONS" -gt 0 ] && echo "Max:        $MAX_ITERATIONS iterations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

notify "🚀" "Ralph Started" "Mode: $MODE | Branch: $CURRENT_BRANCH"

if [ "$MODE" != "review" ] && [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: $PROMPT_FILE not found"
    exit 1
fi

while true; do
    if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
        echo "Reached max iterations: $MAX_ITERATIONS"
        break
    fi

    case "$MODE" in
        review)
            git diff 2>/dev/null | ai_exec "stdin" "review"
            ;;
        plan|plan-work)
            ai_exec "file:$PROMPT_FILE" "$MODE"
            ;;
        *)
            ai_exec "file:$PROMPT_FILE" "build"
            ;;
    esac

    if [ "$MODE" = "build" ]; then
        run_codex_review
    fi

    security_gate
    push_branch "$CURRENT_BRANCH"

    ITERATION=$((ITERATION + 1))

    if [ $((ITERATION % 5)) -eq 0 ]; then
        notify "🔄" "Ralph Progress" "Completed $ITERATION iterations on $CURRENT_BRANCH (model: $AI_MODEL)"
    fi

    echo -e "\n\n======================== LOOP $ITERATION ($AI_MODEL) ========================\n"
done

