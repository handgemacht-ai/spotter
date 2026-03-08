# Design Spec: Approach C (Clean Architecture) for Multi-Root Transcripts

Status: Proposed  
Scope: App runtime + scripts/docs alignment  
Primary goal: Support transcript discovery/sync across multiple roots with one explicit contract and zero duplicated fallback logic.

## 1. Problem

Transcript root resolution is currently spread across multiple runtime paths:

- `Spotter.Services.TranscriptDiscovery`
- `Spotter.Transcripts.Jobs.SyncTranscripts`
- `SpotterWeb.SessionHookController` (live tail path)
- Mix/runtime scripts that assume one root (`transcripts_dir`)

This causes:

- Inconsistent fallback order (`transcripts_dir` vs hardcoded `~/.claude/projects`)
- Duplicate root-construction logic
- Hard-to-test behavior drift between app runtime and scripts

## 2. Approach C Summary

Introduce a clean architecture boundary for transcript roots:

- Domain contract: root resolution and selection rules
- Application services: discover/list/find/live-path use cases
- Adapters: DB/TOML/env-backed resolver implementation
- Framework layer: controllers/jobs/scripts call use cases only, never rebuild fallback chains

The core principle: **all root decisions flow through one resolver contract**.

## 3. Architecture

### 3.1 Domain Contracts (new)

#### `Spotter.Transcripts.Roots.Root`

Canonical root value object:

- `id :: String.t()` stable identifier (hash of normalized path)
- `path :: String.t()` absolute expanded path
- `source :: :override | :db_multi | :db_legacy | :toml_multi | :toml_legacy | :default`
- `priority :: non_neg_integer()`
- `readable? :: boolean()`
- `writable? :: boolean()`
- `exists? :: boolean()`

Invariants:

- `path` is absolute and deduped by normalized path
- Output order is deterministic (`priority desc`, then `path asc`)
- Contract does not raise; warnings are returned as data

#### `Spotter.Transcripts.Roots.Resolver` (behavior)

```elixir
@callback resolve(keyword()) ::
  {:ok, [Spotter.Transcripts.Roots.Root.t()], [warning :: map()]}
  | {:error, reason :: term()}
```

Options contract:

- `:override_roots` list of paths (highest precedence, used by tests/manual jobs)
- `:require_writable?` default `false`

Semantics:

- Invalid/unreadable roots are dropped with warning metadata
- If all configured roots are invalid, fallback to default root with warning
- No side effects except telemetry and optional warnings log

#### `Spotter.Transcripts.Roots.Catalog` (pure service)

Pure helper APIs over resolved roots:

- `roots/1`
- `project_dirs_for_pattern/2`
- `find_session_file/2`
- `live_transcript_file/3` (session start tail path)

### 3.2 Application Layer (use cases)

Refactor use cases to depend on `Roots.Catalog`:

- Discovery/listing (`TranscriptDiscovery`, `TranscriptListing`)
- Sync (`SyncTranscripts.perform/1`, `sync_session_by_id/2`)
- Session start live tail path (`SessionHookController`)

### 3.3 Adapters / Infra

#### Runtime adapter (`Spotter.Config.Runtime`)

Add multi-root accessor while keeping legacy compatibility:

- `transcript_roots/0 -> {roots :: [String.t()], source :: atom()}`
- keep `transcripts_dir/0` as compatibility shim (`hd(transcript_roots())`)

Precedence:

1. Override (`opts[:override_roots]`)
2. DB `transcript_roots` (new setting, JSON array string)
3. DB `transcripts_dir` (legacy)
4. TOML `transcript_roots` (new optional array)
5. TOML `transcripts_dir` (legacy)
6. Default `~/.claude/projects`

#### Settings adapter (`Spotter.Config.Setting`)

Allow key `transcript_roots` in addition to `transcripts_dir`.

## 4. Implementation Boundaries

### In Scope (runtime)

- Centralize root logic into resolver/catalog boundary
- Replace duplicated `transcript_search_roots/1` implementations
- Update discovery/sync/session-start paths to consume resolver
- Preserve OTEL spans; add resolver-level attributes:
  - `spotter.transcript_roots.count`
  - `spotter.transcript_roots.sources`
  - `spotter.transcript_roots.invalid_count`

### In Scope (scripts + docs alignment)

- Add one machine-readable command for scripts:
  - `mix spotter.transcript-roots --format=json`
- Migrate scripts that currently hardcode `~/.claude/projects` to consume this output (or explicit flag override)
- Update README + QUICKSTART + E2E fixture docs to explain multi-root behavior and precedence

### Out of Scope

- Parser schema changes (`JsonlParser`)
- Session/message/subagent data model changes
- UI redesign for root management
- Hook payload contract changes

## 5. Strong Contract Decisions

1. Deterministic ordering is mandatory for reproducible sync and tests.
2. Resolver never raises; callers get `{:ok, roots, warnings}`.
3. All callers use the same root list; no local fallback reconstruction.
4. Legacy `transcripts_dir` remains supported until explicit removal phase.
5. Script and runtime paths use the same precedence model.

## 6. Tradeoffs

### Benefits

- Removes drift between discovery/sync/live-tail behavior
- Single place to test root precedence and error handling
- Easier future extension (per-project root policies, remote mounts)
- Safer script/runtime parity for E2E and local tooling

### Costs

- Additional modules/abstractions for a currently small surface
- Slight upfront migration complexity to preserve legacy compatibility
- Requires updating tests across several existing modules

### Rejected Alternatives

- Minimal patch in each caller:
  - Lower initial effort, but keeps duplication and drift risk
- Global helper returning list of strings only:
  - Better than duplication, but too weak for contracts (no source/priority/warnings)

## 7. Rollout Plan

1. Introduce contracts + adapter with no behavior change (legacy-compatible defaults).
2. Migrate runtime call sites one by one to resolver/catalog.
3. Add script command + migrate scripts.
4. Update docs.
5. Deprecate direct `transcripts_dir` reads in runtime modules.

## 8. Test Matrix

### 8.1 Unit Tests (new)

| Area | Module | Cases |
|---|---|---|
| Resolver precedence | `Spotter.Transcripts.Roots.ResolverTest` | override > db_multi > db_legacy > toml_multi > toml_legacy > default |
| Path normalization/dedupe | same | tilde expansion, duplicate paths, trailing slash normalization |
| Invalid roots handling | same | unreadable/missing paths produce warnings; fallback root still returned |
| Deterministic ordering | same | stable order independent of input order |

### 8.2 Contract Tests (new)

| Contract | Module | Cases |
|---|---|---|
| Resolver behavior contract | `Spotter.Transcripts.Roots.ResolverContractTest` | no raise, tuple shape, source labels, warning schema |
| Catalog search contract | `Spotter.Transcripts.Roots.CatalogTest` | `find_session_file/2`, `live_transcript_file/3`, first-hit semantics |

### 8.3 Runtime Integration Tests (update/add)

| Runtime Surface | Target Test File | Cases |
|---|---|---|
| Discovery | `test/spotter/services/transcript_discovery_test.exs` | discovers across multiple roots, dedupes by session id/file path strategy |
| Listing | `test/spotter/services/transcript_listing_test.exs` | pagination/sort still correct with merged multi-root set |
| Sync by ID | `test/spotter/transcripts/jobs/sync_transcripts_test.exs` | finds session file across roots, consistent precedence |
| Session start | `test/spotter_web/controllers/session_hook_controller_test.exs` | live transcript path uses resolver; writable root fallback behavior |
| Runtime config | `test/spotter/config/runtime_test.exs` | `transcript_roots/0` precedence + legacy shim |

### 8.4 Scripts / Tooling Tests (update/add)

| Surface | Target | Cases |
|---|---|---|
| Mix command | `test/mix/tasks/spotter.transcript_roots_test.exs` | JSON output shape, override flags, empty/invalid handling |
| E2E snapshot script | `scripts/e2e/snapshot_transcripts.sh` + script tests | consumes resolver output or explicit roots; multi-root selection deterministic |
| Live configure task | `test/mix/tasks/spotter.live.configure_test.exs` | sets `transcript_roots` and preserves `transcripts_dir` compatibility |

### 8.5 Regression Matrix

| Risk | Guard |
|---|---|
| Existing single-root installs break | keep `transcripts_dir` shim + compatibility tests |
| OTEL visibility lost | assert root resolver span attributes in tests |
| Script/runtime divergence returns | script command uses same runtime resolver contract |

## 9. Docs Alignment Checklist

- Update README transcript configuration section:
  - new `transcript_roots` support
  - precedence and compatibility with `transcripts_dir`
- Update `docs/QUICKSTART.md` import section with multi-root note
- Update fixture snapshot docs for multi-root source selection
- Add migration notes for operators currently setting only `transcripts_dir`

## 10. Acceptance Criteria

1. One resolver contract used by discovery, sync, and session-start live path.
2. No module outside resolver/catalog rebuilds root fallback logic.
3. Scripts consume resolver output (or explicit override) rather than hardcoded root.
4. Legacy `transcripts_dir` setups continue to work without config changes.
5. Test matrix above is implemented and passing.
