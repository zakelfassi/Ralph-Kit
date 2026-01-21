# Ralph Kit

This repository contains the **Ralph framework**: scripts + templates that add “Ralph-style” agent loops to any codebase.

## Install into another repo
From this repo:
```bash
./install.sh /path/to/other/repo --wrapper
```

From within a target repo that already has this kit vendored at `ralph/`:
```bash
./ralph/install.sh --wrapper
```

## Run (in the target repo)
```bash
./ralph/bin/loop.sh plan 1
./ralph/bin/loop.sh 10
```

Daemon mode:
```bash
./ralph/bin/ralph-daemon.sh 300
```

## Notes
- Runtime state/logs go in `.ralph/` (installer adds this to the target repo `.gitignore`).
- Optional Slack integration uses `.env.local` with `SLACK_WEBHOOK_URL=...`.
