# User Requests

Add requests below. Ralph will process them in order.

## Format

```
## [Request Title]
- Priority: high/medium/low
- Type: feature/fix/refactor/docs

Description of what you want...

### Acceptance Criteria
- Specific, verifiable criterion 1
- Specific, verifiable criterion 2
```

## Daemon Control Flags

Add these anywhere in this file to control the Ralph daemon:

- `[PAUSE]` - Pause the daemon loop
- `[REPLAN]` - Run planning once, then continue building
- `[DEPLOY]` - Run the configured deploy command

## Ingested Reports

When using `./ralph/bin/ingest-report.sh`, entries are appended below with:
- `Source: report:<hash>` - For idempotency tracking
- `CreatedAt: <timestamp>` - When ingested

---

<!-- Add your requests below this line -->

