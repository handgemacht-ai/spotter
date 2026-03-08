# Product Skill Template

> This template defines what a product skill should document and how.
> Used by bootstrap-product to generate, and by agents to maintain.

## SKILL.md (Index)

Keep SKILL.md slim — it's loaded into context on every activation:

- **Product Summary**: One paragraph (what, who, core value)
- **Domain Map**: Table with domain | purpose | key entities
- **Feature Index**: Table with feature | route | link to feature file
- **References**: Links to `references/*.md` files and `references/features/` directory

## references/features/\<slug\>.md (one file per feature)

Each shipped feature gets its own file. The slug is a kebab-case name (e.g., `session-detail.md`).

### Required sections

```markdown
# <Feature Name>

## Why This Exists
What problem does this solve? What user need prompted it? (2-3 sentences)

## What It Does
User-visible behavior. (2-3 sentences)

## User Flow
1. Step-by-step from user perspective
2. ...

## How It Works
Technical implementation: data flow, key patterns, background jobs, real-time updates.

## Routes & Endpoints
| Method | Path | Purpose |
|--------|------|---------|
| GET | /... | ... |

## Key Files
Repo-relative paths grouped by layer:
- **LiveView**: `lib/spotter_web/live/...`
- **Service**: `lib/spotter/services/...`
- **Component**: `lib/spotter_web/components/...`

## Data Model
Which resources are involved and how they relate (prose — full ER diagrams live in data-model.md).

## Constraints & Edge Cases
Business rules, limits, known quirks.
```

### Optional sections

- **Bead ID**: If the feature was tracked as a bead/epic

## references/data-model.md

Per domain, include:
- Mermaid ER diagram showing entities + relationships + cardinality
- Brief prose explaining non-obvious relationships
- Cross-domain relationship section at the end

## references/api-surface.md

Table: method | path | purpose | auth required

## references/roles-and-permissions.md

Table: role | capabilities | restrictions

## references/external-integrations.md

Table: service | purpose | module/file | config

## references/known-limitations.md

Bullet list of gaps, missing features, known issues.

## Maintenance Rules

- Add a new `references/features/<slug>.md` after shipping each feature/epic
- Update existing feature files when behavior changes significantly
- Update `data-model.md` when domains or entities change
- Update the Feature Index table in `SKILL.md` when adding/removing feature files
- The `Product Skill Delta` section in epics shows exactly what needs updating
- Run `/bootstrap-product <rig>` to regenerate from scratch if the skill drifts significantly
