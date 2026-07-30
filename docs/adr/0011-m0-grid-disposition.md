# ADR-0011 — Reject the full-grid `NSTableView` composition after the M0 grid spike

- **Status:** Accepted as a spike disposition; full-grid `NSTableView`
  candidate rejected; bounded custom native renderer selected as the planning
  candidate; production implementation gated
- **Date:** 2026-07-30
- **Supersedes:** The result-grid renderer choice in ADR-0001 only
- **Related:** ADR-0001, DF-M0-004, BF-02, BF-03, R-10, R-11, R-18

## Context

ADR-0001 selected a SwiftUI shell with focused AppKit controls and named a
view-based `NSTableView` as the planning candidate for result presentation. It
required a disposable million-row and wide-column spike before implementation.

DF-M0-004 constructed that spike from deterministic typed BF-02 and BF-03
fixtures. The durable evidence record is
[`DF-M0-004-appkit-grid-evidence.md`](../reports/DF-M0-004-appkit-grid-evidence.md),
and its exact source is commit
`7acdec023b1debab1daf4af354f8b9968ee9f32b`.

The spike deliberately separates renderer concerns from database execution. It
uses formula-generated data, bounded page and pending-edit stores, stable
logical identities, deferred large-value metadata, normalized type styling and
synthetic cancellation. It contains no driver, network, FFI, credential, SQL
write or path that can apply a pending edit.

## Findings

The model and service boundaries produced useful positive evidence:

- BF-02 represents one million and ten million logical rows without
  materializing row cardinality;
- the page cache has independent item and byte ceilings, while pending edits
  have separate admission limits and survive cache churn;
- SQL `NULL`, not-loaded, empty text and empty binary remain distinct typed
  states;
- stable row, column and cell identity survives the exercised selection,
  reorder, resize, theme and cache-pressure operations;
- 1/10/100 MiB JSON/BLOB fixtures remain bounded deferred descriptors; and
- grid-side synthetic cancellation acknowledges the request and suppresses a
  late value without claiming driver, network or FFI cancellation.

Those contracts do not rescue the proposed renderer. `NSTableView` virtualizes
rows but creates a physical column and available cell view graph across the
whole wide schema. BF-03 therefore expands far beyond the geometrically visible
two-dimensional viewport: the run retained 17,000 cell views for 374
geometrically visible cells, consumed 1.97 GiB incremental `phys_footprint` and
required 1,353.64 seconds. BF-02 1M and 10M also failed the absolute memory
gate at 254.11 MiB and 252.30 MiB incremental footprint, although their 1.81 MiB
delta supports cardinality independence. The two-table frozen-column
composition also fails the one-logical-accessibility-table contract: the
ignored frozen projection owns three columns, while the exposed primary table
owns only the remaining 497 columns. Metadata derived from the fixture cannot
substitute for the actual accessibility tree, and manual VoiceOver behavior is
not established.

Forced layout/display and scripted scroll-step durations remain diagnostic
proxies. They do not observe Core Animation presentation and cannot establish
first paint, theme-to-frame latency, FPS, hitch incidence or the consecutive
hitch gate. The Apple M1/16 GiB/macOS 14 floor and eight-hour soak also remain
untested.

## Decision

Reject the current full-grid `NSTableView` plus synchronized frozen-table
composition as the primary renderer for the required BF-03 result grid.

Select a bounded custom native two-dimensional renderer as the next planning
candidate. This is a component direction, not authorization to write or ship
production code. A reviewed implementation must preserve renderer-independent
`ResultGrid` contracts and meet all of the following design constraints:

1. Virtualize both logical rows and logical columns with bounded overscan.
2. Cap retained cell/tile/layer objects and their bytes independently of total
   row and column cardinality.
3. Expose one unified logical table, header, row and cell accessibility
   hierarchy across frozen and scrollable regions without duplicate focus.
4. Keep page/cache/fetch, normalized typed values, stable identity, selection,
   pending edits and theme resolution outside the renderer.
5. Update only visible presentation on palette changes and retain non-color
   status indicators.
6. Keep AppKit state on `MainActor`; fetch and processing remain structured,
   bounded and cancellable off the main thread.
7. Never apply edits from renderer reuse, scrolling, eviction or theme events.

The SwiftUI/AppKit shell, TextKit editor and object-tree decisions in ADR-0001
are unchanged. A web grid is not selected by this ADR; adopting one would
require a superseding ADR with equivalent native interaction, accessibility,
security, memory and distribution evidence.

## Re-entry criteria

Production review for the replacement renderer requires:

1. BF-02 1M/10M and BF-03 500×100k runs on the M1/16 GiB/macOS 14 floor.
2. Core Animation presented-frame evidence for cold first paint, steady
   vertical/horizontal scroll and theme changes using the frozen protocol.
3. Incremental physical footprint at or below 150 MiB and no more than 8 MiB
   cardinality delta, with a recorded cache/object inventory.
4. A hard row-and-column viewport object bound proven under resize, reorder,
   frozen columns and memory pressure.
5. Automated unified accessibility-tree assertions plus a documented manual
   VoiceOver, keyboard, focus-order and resize session.
6. Light/Dark, Increase Contrast and Differentiate Without Color evidence with
   contrast warnings for user-defined palettes.
7. Exact selection, scroll anchor and pending-edit preservation across fetch,
   eviction, reorder, theme, pressure and cancellation.
8. Leak diagnostics, repeated open/close and an eight-hour soak.

Any wrong-row or lost-edit observation blocks the renderer regardless of frame
or memory performance.

## Consequences

- ADR-0001 remains accepted for the application-shell strategy, but no longer
  recommends `NSTableView` for the full result grid.
- DF-M2-007 must target a reviewed bounded native two-dimensional renderer and
  remains gated by the re-entry criteria above.
- The renderer-neutral model/service findings may inform a fresh production
  design, but the disposable spike is never copied into a product target.
- R-10 and R-18 remain open; BF-03 has converted a renderer uncertainty into a
  known architecture constraint. R-11 remains release-blocking and unchanged.
- The spike source is removed after the durable report, ADR and sanitized raw
  evidence are committed; a follow-up documentation commit records the exact
  disposal revision.
