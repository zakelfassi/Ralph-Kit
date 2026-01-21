#!/usr/bin/env bash
set -euo pipefail

# Ralph Framework Config
# - This file is safe to commit.
# - Override any value by exporting it before running Ralph.

# Runtime dir (relative to repo root if not absolute)
export RALPH_RUNTIME_DIR="${RALPH_RUNTIME_DIR:-.ralph}"

# Git defaults
export RALPH_DEFAULT_BRANCH="${RALPH_DEFAULT_BRANCH:-main}"
export RALPH_GIT_REMOTE="${RALPH_GIT_REMOTE:-origin}"

# If true, Ralph will try to push after each loop iteration.
# Safe default is false for new repos; enable on a dedicated branch/runner.
export RALPH_AUTOPUSH="${RALPH_AUTOPUSH:-false}"

# Prompt files (relative to repo root)
export RALPH_PROMPT_PLAN="${RALPH_PROMPT_PLAN:-PROMPT_plan.md}"
export RALPH_PROMPT_BUILD="${RALPH_PROMPT_BUILD:-PROMPT_build.md}"
export RALPH_PROMPT_PLAN_WORK="${RALPH_PROMPT_PLAN_WORK:-PROMPT_plan_work.md}"

# Ralph coordination files (relative to repo root)
export RALPH_IMPLEMENTATION_PLAN_FILE="${RALPH_IMPLEMENTATION_PLAN_FILE:-IMPLEMENTATION_PLAN.md}"
export RALPH_STATUS_FILE="${RALPH_STATUS_FILE:-STATUS.md}"
export RALPH_REQUESTS_FILE="${RALPH_REQUESTS_FILE:-REQUESTS.md}"
export RALPH_QUESTIONS_FILE="${RALPH_QUESTIONS_FILE:-QUESTIONS.md}"
export RALPH_CHANGELOG_FILE="${RALPH_CHANGELOG_FILE:-CHANGELOG.md}"

# Optional: command to run after Codex review auto-fixes (e.g. "pnpm test:ci", "npm test", "pytest -q")
export RALPH_TEST_CMD="${RALPH_TEST_CMD:-}"

# Optional: deploy command the daemon runs when it sees [DEPLOY] in REQUESTS.md
export RALPH_DEPLOY_CMD="${RALPH_DEPLOY_CMD:-}"

