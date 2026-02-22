# CLI UX Design Specification: Spotter Local Dev Runtime

**Epic**: sp-cg0o — Spotter Local Dev Runtime
**Author**: designer
**Status**: Draft

---

## 1. Command Structure

All commands go through `just` (a modern `make` alternative). Short, memorable, unix-y.

| Command | Purpose |
|---|---|
| `just up` | Start Dolt + Phoenix |
| `just down` | Stop everything gracefully |
| `just status` | Show service health at a glance |
| `just logs` | Tail combined service logs |
| `just reset` | Down + destroy volumes + up fresh |

No subcommands, no flags for v1. Just verbs.

---

## 2. Prerequisite Checks

Run before any command. Exit non-zero with actionable text on failure.

```
  spotter  prerequisite check failed

    missing: just
    install: https://github.com/casey/just#installation

    missing: overmind (or hivemind)
    install: brew install overmind

  Run the install commands above, then retry.
```

**Rules:**
- Check `just`, `overmind`, `docker`, `mix`, `mysql` (for Dolt readiness check) — in that order
- Batch all missing prerequisites into ONE message (don't fail on first)
- Always include install instructions (URL or command)
- Exit code `1` for missing prerequisites
- No color in the error block — just clean indented text so it's pipe-friendly

---

## 3. Startup Output (`just up`)

Clean, scannable, minimal. One line per service as it comes up.

```
  spotter  starting local runtime...

    dolt       ● starting    port 13307
    phoenix    ○ waiting     (needs dolt)

  spotter  dolt ready (2.1s)

    dolt       ● running     port 13307
    phoenix    ● starting    port 1100

  spotter  migrations applied (0.4s)
  spotter  all services running

    http://localhost:1100

  Ctrl+C to stop all services.
```

**Design principles:**
- `●` filled circle = active/starting, `○` hollow = waiting
- Service name left-aligned, padded to 10 chars
- Status keyword: `starting`, `running`, `waiting`, `stopped`, `error`
- Port shown on same line — the most useful debug info
- Final URL on its own line — the thing you actually want
- Timing shown for slow operations (Dolt readiness, migrations)
- No banner art, no version numbers, no noise

---

## 4. Status Output (`just status`)

Snapshot view. Works whether services are up, down, or mixed.

### All running:
```
  spotter  local runtime status

    dolt       ● running     port 13307    pid 42381
    phoenix    ● running     port 1100     pid 42390

    uptime: 2h 14m
    url:    http://localhost:1100
```

### Partially running:
```
  spotter  local runtime status

    dolt       ● running     port 13307    pid 42381
    phoenix    ✕ stopped

    uptime: 2h 14m

  Note: phoenix is down. Run `just up` to restart.
```

### All stopped:
```
  spotter  no services running

  Run `just up` to start the local runtime.
```

**Symbols:**
- `●` = running (green in terminal, plain in pipes)
- `✕` = stopped (dim/grey in terminal)
- `!` = error state (red in terminal)

**Color strategy:**
- Use ANSI colors when stdout is a TTY
- Strip colors when piped (detect with `[ -t 1 ]`)
- Green: running services, success messages
- Red: errors, failed services
- Dim/grey: stopped services, secondary info
- Bold white: headers (`spotter`)

---

## 5. Shutdown Output (`just down`)

```
  spotter  stopping local runtime...

    phoenix    ✕ stopped
    dolt       ✕ stopped

  spotter  all services stopped
```

**Rules:**
- Stop in reverse order (Phoenix first, Dolt last)
- One line per service as it stops
- Clean exit, no lingering output

---

## 6. Error States

### Service fails to start:
```
  spotter  startup error

    dolt       ! error       port 13307 already in use

  Fix: kill the process using port 13307, or change SPOTTER_DOLT_PORT.
  Run `just down` first if a previous session is still running.
```

### Service crashes during runtime:
```
  spotter  service crashed

    phoenix    ! error       exit code 1

  Check logs: just logs
  Restart:    just up
```

**Error design principles:**
- Always suggest a fix or next action
- Reference the specific command to run
- Show the port/pid/exit code — concrete debugging info
- Never show stack traces in the summary (that's what `just logs` is for)

---

## 7. ANTHROPIC_API_KEY Handling

The key is optional. When absent, Spotter starts fully — AI features degrade gracefully.

### On startup (key absent):
```
  spotter  starting local runtime...

    dolt       ● running     port 13307
    phoenix    ● running     port 1100

  spotter  all services running

    http://localhost:1100

  Note: SPOTTER_ANTHROPIC_API_KEY not set. AI features disabled.
  Ctrl+C to stop all services.
```

One line. Not an error. Not a warning. Just a note.

### On startup (key present):
No mention of it at all. Silent success is the best UX.

---

## 8. Overmind/Procfile Integration

The Procfile defines the process tree. Overmind supervises it.

```procfile
dolt:    docker compose -f docker-compose.dolt.yml up
phoenix: mix phx.server
```

**Overmind config (`.overmind.env`):**
```
OVERMIND_PROCFILE=Procfile.dev
```

- Phoenix depends on Dolt, handled by readiness check in Justfile (not Overmind)
- OTEL/Jaeger is managed externally (shared workspace infrastructure) — not part of the local runtime

---

## 9. Typography & Spacing

```
  spotter  <message>
                              ← 2-space indent for the "spotter" prefix
    service    ● status       ← 4-space indent for service lines
                              ← blank line between sections
```

- **Header prefix**: `spotter` in bold, followed by 2 spaces, then the message
- **Service lines**: 4-space indent, service name padded to 10 chars, symbol, status padded to 12 chars, then optional details
- **Sections** separated by one blank line
- **No trailing whitespace**
- **Final newline** after last output line

---

## 10. Justfile Structure

```just
# Spotter Local Dev Runtime

set dotenv-load

default:
    @just --list

up:
    @scripts/runtime/check-prereqs.sh
    @scripts/runtime/up.sh

down:
    @scripts/runtime/down.sh

status:
    @scripts/runtime/status.sh

logs:
    @overmind echo

reset:
    @just down
    @scripts/runtime/reset.sh
    @just up
```

Justfile is thin — delegates to scripts in `scripts/runtime/`. This keeps the Justfile readable and the scripts testable independently.

---

## Design Rationale

1. **No banner/ASCII art**: Developers see startup output hundreds of times. Every unnecessary line is friction.
2. **Consistent indentation**: The 2/4 space pattern creates visual hierarchy without box-drawing characters.
3. **Symbols over words**: `●` vs `✕` vs `!` scan faster than colored text alone.
4. **Port numbers always visible**: The #1 thing you need when debugging "is it running?"
5. **Actionable errors**: Every error state tells you what to do next.
6. **Two-service simplicity**: Core runtime is just Dolt + Phoenix. OTEL/Jaeger managed externally as shared workspace infra.
7. **Pipe-friendly**: No color codes when piped, clean text output for scripting.
