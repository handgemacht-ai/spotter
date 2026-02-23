# Changes

## 2026-02-23

- Hardened session-lanes end-to-end tests with deterministic test data, stable selectors, and reusable test infrastructure so lane views stay reliable across changes.

## 2026-02-23 (earlier)

- Improved reliability of session tracing by fixing span context leaks in telemetry handlers and adding test utilities to prevent regressions.
- **Internal:** Added performance tracking for parallel transcript lanes computation and view mode switching.
