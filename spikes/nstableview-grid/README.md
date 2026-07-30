# DF-M0-004 disposable NSTableView grid spike

This standalone package tests one planning hypothesis: a view-based native
`NSTableView` composition can render deterministic BF-02/BF-03 typed data with
bounded memory while preserving stable selection, scroll and pending-edit
identity.

It is not a product module. It has no database, network, FFI, credential,
connection-string, SQL execution or SQL write path. The fixture is generated
from row/column coordinates and must not materialize its 1M/10M-row logical
cardinality.

## Boundaries

- `GridSpikeCore` owns normalized synthetic values, stable identities, the
  deterministic generator, bounded page cache, pending-edit overlay, theme
  tokens and synthetic fetch cancellation.
- `GridSpikeAppKit` owns only the `@MainActor` table/cell/frozen-column harness,
  keyboard/accessibility metadata and visible-cell invalidation.
- `GridEvidence` runs a visible-window evidence harness and emits aggregate
  timings and bounded-resource inventory without row payloads.
- Pending edits are never owned or evicted by the page cache. No edit can be
  applied to a database in this spike.
- Declared 1/10/100 MiB JSON/BLOB cells are metadata-only and never allocate the
  declared payload.

## Frozen measurement contract

The authoritative gates are fixed in `docs/PERFORMANCE_BUDGET.md` section 3.1
before this package is measured. In particular, layout/scroll-step timings are
diagnostic proxies and are not reported as presented-frame FPS. Manual
VoiceOver and the M1/16 GiB release floor remain separate evidence gates.

The implementation deliberately records both geometrically visible cells and
all cell views retained by `NSTableView`. A wide table that instantiates views
for off-screen columns is a feasibility failure even when vertical reuse and
the page-cache byte ceiling work.

## Run

Full Xcode is required because the active Command Line Tools selection cannot
run native `xcodebuild` in this workspace:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./scripts/test.sh
```

The script runs strict `swift-format`, warnings-as-errors SwiftPM build/tests,
native arm64 Xcode build/tests, a release build, and separate BF-02 1M, BF-02
10M, and BF-03 processes. Each process opens a synthetic visible AppKit window,
uses one warm-up plus ten samples, reports raw/median/nearest-rank-p95/worst/CV,
and records physical footprint above a blank visible-window baseline. The
runner's layout/display and scroll-step numbers are named proxies. Use
Instruments Animation Hitches for presented-frame evidence and perform a
separate manual VoiceOver session.

`GRID_SPIKE_SCROLL_SECONDS` exists only for quick harness diagnosis; durable
evidence uses the frozen 10-second protocol. `GRID_SPIKE_SAMPLES` may increase
but not reduce the minimum ten samples.

## Disposal

After commands, raw samples, limitations and disposition are recorded in
`docs/reports/DF-M0-004-appkit-grid-evidence.md` and ADR-0011, this entire
directory is deleted in a separate disposal commit. Production code must be
implemented later from reviewed contracts, not copied from this prototype.
