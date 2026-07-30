# ADR-0010 — Conditionally retain TextKit 2 after the M0 editor spike

- **Status:** Accepted as a spike disposition; planning candidate retained
  conditionally; production implementation gated
- **Date:** 2026-07-30
- **Supersedes:** None; refines the validation state of ADR-0001
- **Related:** ADR-0001, DF-M0-003, R-18, R-24

## Context

ADR-0001 selected a SwiftUI shell with focused AppKit controls and named
`NSTextView`/TextKit 2 as the planning candidate for the SQL editor. It required
large-file, keyboard, accessibility and recovery evidence before implementation.

DF-M0-003 built a disposable explicit TextKit 2 graph and exercised deterministic
10 MiB and 100 MiB BF-01 fixtures. The durable record is
[`DF-M0-003-textkit-editor-evidence.md`](../reports/DF-M0-003-textkit-editor-evidence.md),
and the exact source is commit
`130bd3a79e48bb2b029e1624132eeb5b241fde59`.

## Findings

Positive developer-host evidence includes:

- zero ordinary TextKit 1 fallback events and a passing fallback-observer
  positive control;
- bounded visible analysis, bounded rendering attributes and chunked find;
- correct middle/near-end/absent find results under 300 ms p95 at 100 MiB;
- explicit 100 MiB large-file mode;
- native edit revision invalidation, grouped undo/redo byte accounting and a
  100-level history cap;
- direct selector and accessibility-metadata smoke;
- successful SwiftPM/Xcode suites, Allocations/Time Profiler target exits and
  recorded residual framework leak output.

The evidence does **not** establish input-event-to-frame paint, an editor-only
RSS ceiling, the M1/16 GiB floor, real key-equivalent routing, manual VoiceOver,
durable crash recovery, Light/Dark runtime behavior or signposted active-worker
cancellation. The bounded highlighter reached its 1,024-span output cap.

## Decision

Retain `NSTextView` with TextKit 2 as the preferred **planning candidate** behind
a narrow AppKit presentation interface. Do not accept it for production
implementation yet, do not import the spike into an app target and do not
describe the BF-01 editor acceptance criterion as passed.

The production design must keep:

1. Explicit TextKit 2 component construction and a regression alarm for
   unintended TextKit 1 fallback.
2. Viewport-bounded decoration and cancellable analysis snapshots carrying a
   document revision; stale results cannot mutate current presentation state.
3. Bounded chunked find and explicit large-file feature degradation.
4. `MainActor` ownership for AppKit state, with analysis/file work in structured
   cancellable services.
5. Native undo semantics with an explicit bounded-history/resource policy.

SQL dialect parsing and safety classification remain outside the view/editor
boundary. The editor never executes SQL or constructs a database connection.

## Re-entry criteria

Production review requires a visible M1/16 GiB benchmark for true
input-to-presented-frame latency; an approved editor-specific RSS ceiling and
soak; real shortcut/responder and manual VoiceOver evidence; durable draft/crash
recovery; appearance/focus checks; and worker-start/signposted cancellation.
Parser/completion dependencies require their own license, advisory, fuzz and
dialect-quality gate.

If TextKit 2 fails any release-blocking re-entry gate, evaluate a narrowly
scoped native alternative for the failing component. A whole-stack web editor
or third-party engine is not adopted without a superseding ADR and equivalent
native UX, accessibility, security, memory and distribution evidence.

## Consequences

- ADR-0001 remains accepted for planning but not accepted for SQL-editor
  production implementation.
- DF-M2-003 stays gated by the re-entry criteria above.
- R-18 is reduced by positive feasibility evidence but remains open; R-24 is
  unchanged because the spike contains no production SQL parser.
- The disposable source is removed after the report/ADR commit. Git history
  retains the exact evidence source; future code is rebuilt under reviewed
  production boundaries.
