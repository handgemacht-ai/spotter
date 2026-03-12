# Quickstart

## Start Spotter

```bash
just otel-up
just up
```

On a fresh checkout, `just up` installs missing Mix deps and asset deps automatically before Phoenix starts.
If shared OTEL is not already running, `just up` exits non-zero and tells you to run `just otel-up` or `cd /srv/handgemacht/handgemacht && just obs-up`.

Open `http://localhost:1100` in your browser.

## Key Pages

- **Dashboard** (`/`) — Shows ongoing sessions across all projects. Sessions appear live when started and are marked finished when ended.
- **Sessions** (`/sessions`) — Browse all session transcripts filtered by project. Includes import, hide/unhide, and pagination. Click "Review" to open a session detail view.
- **Reviews** (`/reviews`) — Open review annotations across sessions.
- **Retros** (`/retros`) — Session retrospectives.
- **History** (`/history`) — Git commit history linked to sessions.
- **File Metrics** (`/file-metrics`) — Heatmap and co-change analysis.
- **Telemetry** (`/telemetry/commands`) — Shell command telemetry.

## Import Sessions

1. Navigate to **Sessions** (`/sessions`).
2. Click **Import** in the page header.
3. Select transcripts from the file listing and click **Import Selected**.

## Stop Spotter

```bash
just down
```
