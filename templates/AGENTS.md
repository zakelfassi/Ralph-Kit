# Project Operational Guide

This file contains project-specific guidance for Ralph. Keep it brief and operational.

## Project Structure
```
specs/          # Feature specifications (Ralph reads these)
docs/           # Product/tech docs (Ralph reads these)
src/            # Source code (adjust paths as needed)
```

## Build & Run
```bash
# TODO: Add commands for this repo
# pnpm install && pnpm dev
```

## Backpressure Commands
```bash
# Typecheck (run before committing)
# pnpm tsc --noEmit

# Tests (run before committing)
# pnpm test

# Lint (run before committing)
# pnpm lint
```

## Codebase Patterns
<!-- Add discovered patterns here as you work -->
- Prefer small, focused commits
- Update `IMPLEMENTATION_PLAN.md` when scope changes
- Use `./ralph/bin/ask.sh` when blocked or decisions needed

## Modes

**Checklist Lane** (default):
- Uses `IMPLEMENTATION_PLAN.md` as the task list
- Run: `./ralph.sh plan` then `./ralph.sh build`
- Progress in `STATUS.md` and `CHANGELOG.md`

**Tasks Lane** (optional):
- Uses `prd.json` for machine-readable task tracking
- Run: `./ralph.sh tasks` or `./ralph/bin/loop-tasks.sh`
- Progress in `progress.txt`

## Important Notes
- Keep this file operational only
- Status updates and progress notes belong in `IMPLEMENTATION_PLAN.md` or `progress.txt`
- A bloated AGENTS.md pollutes every future loop's context
