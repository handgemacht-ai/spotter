# Data Model

> Mermaid ER diagrams per resource group. See individual [feature files](features/) for how each feature uses these resources.

## Core Session Hierarchy

```mermaid
erDiagram
    Project ||--o{ Session : has
    Session ||--o{ Message : has
    Session ||--o{ Subagent : has
    Subagent ||--o{ Message : has
    Session }o--|| Project : belongs_to
```

Project is the top-level anchor. Each project has many sessions. Sessions contain messages (the transcript) and subagents (team members). Messages can belong to either the session directly or to a subagent within the session.

## Annotations

```mermaid
erDiagram
    Annotation }o--|| Session : belongs_to
    Annotation }o--|| Subagent : belongs_to
    Annotation }o--|| Project : belongs_to
    Annotation }o--|| Commit : belongs_to
    Annotation }o--|| CommitHotspot : belongs_to
    Annotation ||--o{ AnnotationMessageRef : has
    Annotation ||--o{ AnnotationFileRef : has
    AnnotationMessageRef }o--|| Message : references
    AnnotationFileRef }o--|| Project : scoped_to
```

Annotations are polymorphic — they can be attached to a session, subagent, project, commit, or hotspot (all nullable foreign keys). Each annotation tracks its `source` (where it was created) and `purpose` (review or explain). Message refs link to the transcript messages that were selected. File refs specify file paths with line ranges.

## File & Change Tracking

```mermaid
erDiagram
    Session ||--o{ FileSnapshot : has
    Session ||--o{ ToolCall : has
    Session ||--o{ SessionRework : has
```

`FileSnapshot` captures file state before/after tool execution (content_before, content_after, change_type). `ToolCall` records each tool invocation with error status. `SessionRework` tracks files edited multiple times in a session (detected during transcript sync).

## Git Commits

```mermaid
erDiagram
    Commit ||--o{ CommitFile : has
    Session ||--o{ SessionCommitLink : has
    Commit ||--o{ SessionCommitLink : has
    SessionCommitLink }o--|| Session : links
    SessionCommitLink }o--|| Commit : links
```

`SessionCommitLink` is the join table between sessions and commits, with `link_type` (4 values: observed_in_session, descendant_of_observed, patch_match, file_overlap), `confidence` (0.0-1.0), and `evidence` (map). Upserted on `{session_id, commit_id}` identity to prevent duplicates.

## Code Analysis

```mermaid
erDiagram
    Project ||--o{ CommitHotspot : has
    Commit ||--o{ CommitHotspot : has
    Project ||--o{ FileHeatmap : has
    Project ||--o{ CoChangeGroup : has
    CoChangeGroup ||--o{ CoChangeGroupCommit : has
    CoChangeGroup ||--o{ CoChangeGroupMemberStat : has
```

`CommitHotspot` marks code regions with repeated changes, scored 0-100. `FileHeatmap` tracks per-file change frequency over a rolling window. `CoChangeGroup` identifies files that change together, with member stats (size, LOC) and individual commit records.

## Team & Retrospectives

```mermaid
erDiagram
    Project ||--o{ Team : has
    Team ||--o{ TeamMember : has
    TeamMember }o--|| Session : belongs_to
    Session ||--o{ RetroSubmission : has
    Project ||--o{ RetroSubmission : has
    RetroSubmission ||--o{ RetroItem : has
```

Teams group sessions by team name. Each team member links to a session. Retrospective submissions belong to both a session and a project, containing categorized items with ratings.

## Events & Telemetry

```mermaid
erDiagram
    RawHookEvent {
        string session_id
        string hook_event_name
        map hook_payload
    }
    ShellCommandEvent {
        uuid session_id
        string command
        string phase
    }
    InstructionsLoadedEvent {
        uuid session_id
        string file_path
        string memory_type
    }
```

`RawHookEvent` stores complete hook payloads as received. `ShellCommandEvent` and `InstructionsLoadedEvent` are extracted from raw events by dedicated extractors. These are standalone resources (no foreign key relationships to other tables) — linked to sessions via `session_id` UUID matching.

## Internal State

```mermaid
erDiagram
    Project ||--o| ProjectIngestState : has
    Team ||--o| ComputedLaneCache : has
```

`ProjectIngestState` tracks last-run timestamps for commit ingestion, heatmap, and co-change computation (prevents redundant recomputation). `ComputedLaneCache` stores pre-computed parallel lane payloads as Erlang binary terms per team.

## Config Domain

```mermaid
erDiagram
    Setting {
        string key
        string value
    }
```

`Spotter.Config.Setting` — simple key-value store for runtime configuration. Currently supports `transcripts_dir` key. Separate Ash domain (`Spotter.Config`).

## Cross-Domain Relationships

Project is the top-level anchor connecting all major resource groups:

```mermaid
erDiagram
    Project ||--o{ Session : "sessions"
    Project ||--o{ Annotation : "annotations"
    Project ||--o{ Team : "teams"
    Project ||--o{ FileHeatmap : "heatmaps"
    Project ||--o{ CoChangeGroup : "co-change"
    Project ||--o{ CommitHotspot : "hotspots"
    Project ||--o{ RetroSubmission : "retros"
    Project ||--o| ProjectIngestState : "ingest state"
```
