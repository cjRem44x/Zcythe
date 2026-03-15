# Logging — `@fflog::`

`@fflog::` is Zcythe's built-in flat-file JSON logger. It writes structured log entries as newline-delimited JSON (`JSONL`) — one object per line — with automatic Unix timestamps.

No import or external dependency is needed.

---

## Setup

```
log := @fflog::init("app.log.json")
log.open()
defer log.close()
```

- `@fflog::init(path)` — create a logger pointing at `path`
- `log.open()` — open (or create) the file for writing
- `log.close()` — flush and close (use `defer` so it always runs)

---

## Writing Log Entries

```
log.wr(level, component, message)
```

| Argument | Type | Description |
|----------|------|-------------|
| `level` | `str` | Severity label, e.g. `"INFO"`, `"WARN"`, `"ERROR"` |
| `component` | `str` | Subsystem or module name |
| `message` | `str` | Human-readable description |

### Output Format

Each `log.wr(…)` call appends one line:

```json
{"ts":1773544465,"level":"INFO","component":"Auth","msg":"User logged in"}
```

- `ts` — Unix timestamp (seconds since epoch)
- `level` — the level string you passed
- `component` — the component string you passed
- `msg` — the message string you passed

---

## Convention: Log Levels

There is no enforcement — any string is valid. Common conventions:

| Level | When to use |
|-------|-------------|
| `"TRACE"` | Very fine-grained diagnostic output |
| `"DEBUG"` | Developer diagnostics |
| `"INFO"` | Normal operational events |
| `"WARN"` | Unexpected but recoverable situations |
| `"ERROR"` | Failures that need attention |
| `"FATAL"` | Critical failures before exit |

---

## Complete Example

```
@main {
    log := @fflog::init("service.log.json")
    log.open()
    defer log.close()

    log.wr("INFO",  "Startup",  "Service starting")
    log.wr("DEBUG", "Config",   "Loading config from /etc/app.conf")
    log.wr("INFO",  "Config",   "Config loaded successfully")
    log.wr("WARN",  "Cache",    "Cache cold — first request will be slow")
    log.wr("INFO",  "HTTP",     "Listening on :8080")

    # Simulate request handling
    log.wr("DEBUG", "HTTP",     "GET /api/users")
    log.wr("INFO",  "DB",       "Query executed in 12ms")
    log.wr("DEBUG", "HTTP",     "200 OK")

    log.wr("INFO",  "Shutdown", "Graceful shutdown complete")
}
```

Resulting `service.log.json`:
```json
{"ts":1773544390,"level":"INFO","component":"Startup","msg":"Service starting"}
{"ts":1773544390,"level":"DEBUG","component":"Config","msg":"Loading config from /etc/app.conf"}
{"ts":1773544390,"level":"INFO","component":"Config","msg":"Config loaded successfully"}
{"ts":1773544390,"level":"WARN","component":"Cache","msg":"Cache cold — first request will be slow"}
{"ts":1773544390,"level":"INFO","component":"HTTP","msg":"Listening on :8080"}
...
```

---

## Multiple Loggers

You can have more than one logger open simultaneously — for example, a general log and an audit log:

```
@main {
    app_log   := @fflog::init("app.log.json")
    audit_log := @fflog::init("audit.log.json")

    app_log.open()
    audit_log.open()
    defer app_log.close()
    defer audit_log.close()

    app_log.wr("INFO",  "Auth",  "Login attempt")
    audit_log.wr("AUDIT", "Auth", "user:alice ip:192.168.1.10")
}
```

---

## Processing Log Files

Since each line is a valid JSON object, log files are easy to process with standard tools:

```bash
# Show all ERROR lines
grep '"level":"ERROR"' app.log.json

# Pretty-print with jq
cat app.log.json | jq '.'

# Filter by component
cat app.log.json | jq 'select(.component == "DB")'

# Count by level
cat app.log.json | jq -r '.level' | sort | uniq -c
```

---

## Quick Reference

| Call | Description |
|------|-------------|
| `@fflog::init(path)` | Create logger for `path` |
| `log.open()` | Open file for writing |
| `log.close()` | Close file |
| `log.wr(lvl, comp, msg)` | Append JSON log entry |
