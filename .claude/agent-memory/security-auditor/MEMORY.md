# Security Auditor Memory Index

## Spotter Security Patterns (2026-03)

- Ash framework + AshSqlite uses parameterized queries everywhere — SQL injection risk is low
- Recurring antipattern: `inspect(reason)` in controller JSON error responses leaks internal Elixir structures; OTEL spans already capture debug info, so response body should use generic messages
- Image upload uses raw `Plug.Conn.read_body/2` with `application/octet-stream`; Plug.Parsers `pass: ["*/*"]` passes unrecognized content types without consuming body — content-type enforcement at controller level prevents conflicts
- No authentication by design (localhost/tailnet prototype) — IDOR and enumeration are accepted risks
- Go overlay proxy on tailnet forwards responses, so error body sanitization matters if proxy relays to end users
- `mix hex.audit` clean as of 2026-03-23

## Review History

- 2026-03-23: AnnotationController (bead .3, impl-spotter-3t2) — 3 medium, 2 low findings, no critical/high
