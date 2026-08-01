# Performance Budget and Benchmark Plan

Status: Provisional targets; M0 measurements required

Last updated: 2026-08-01

Owners: Performance, macOS, Database Core, feature owners

## 1. Purpose

Performance requirements are correctness constraints for a database client: an unbounded result, cache, queue or task set can crash the app, hide cancellation and increase the blast radius of a malicious server. This document defines measurable budgets, fixtures and release gates. Targets are not claims that the planning-only repository currently meets them.

## 2. Measurement baselines

### 2.1 Reference machines

| Class | Proposed baseline | Purpose |
| --- | --- | --- |
| Minimum supported performance | Apple M1, 8 CPU cores, 16 GB RAM, 256 GB SSD, macOS 14.x latest security update | Release-blocking floor for MVP |
| Current developer | Current base Apple Silicon Mac with 16–24 GB RAM and current supported macOS | Detect day-to-day regressions |
| Stress | Apple Silicon with 32+ GB RAM, throttled network/disk and constrained process memory runs | Throughput/scaling, not a substitute for minimum baseline |

Record exact model, memory, storage free space, OS build, power/thermal state, display configuration, compiler/Xcode/Rust versions, app build, commit, database image digest/version, network latency/bandwidth and fixture checksum. Universal/Intel measurements are out of MVP until the distribution decision changes.

### 2.2 Method

- Use signed or equivalent release-optimized builds with debug logging/telemetry disabled.
- Run at least one warm-up and 10 measured samples for latency; report median, p95 and worst, not only average.
- Use `os_signpost`, Instruments Time Profiler/Allocations/Leaks/Hangs, MetricKit where applicable, Rust tracing/criterion and database-side timing.
- Separate client processing from server/network time.
- Reset deterministic fixture/cache state for cold tests and state it for warm tests.
- Compare to the last accepted baseline; >10% regression in a release-blocking metric requires review even if absolute target still passes.
- A budget change needs measured evidence and user impact, not a larger timeout.

## 3. Product latency and responsiveness budgets

All UI interactions must keep main-thread stalls under 100 ms; routine interactions target a 16.7 ms frame budget on 60 Hz displays and must not repeatedly exceed 33 ms.

| Area | Scenario | MVP target on minimum machine |
| --- | --- | --- |
| App launch | Cold launch to interactive empty workspace, no connection | median ≤1.5 s, p95 ≤2.5 s; main-thread stall ≤100 ms |
| App launch | Warm launch restoring 20 disconnected tabs/drafts | p95 ≤2.0 s to interactive; restoration continues incrementally |
| New window/tab | Empty query tab | p95 ≤100 ms |
| Connection | Local disposable PostgreSQL, no SSH, warm DNS | client overhead p95 ≤250 ms excluding server handshake |
| Connection | 100 ms RTT TLS endpoint | client overhead beyond protocol/network p95 ≤300 ms |
| Cancel UI | Cancel Query action to visible `cancelling` state | ≤100 ms |
| Object tree | Connect to first root nodes | p95 ≤750 ms after connection; no full catalog load |
| Object expand | Node with ≤1,000 children, cached metadata absent | first visible page p95 ≤500 ms plus server time |
| Metadata refresh | Refresh one ≤1,000-object scope with unchanged server | first visible reconciliation p95 ≤750 ms plus server time; unrelated scopes remain usable |
| Object search | Search cached 100k-object index | p95 ≤100 ms; index build off-main/bounded |
| Editor typing | 10 MB SQL file, incremental edit at viewport | p95 input-to-paint ≤16.7 ms, worst routine ≤50 ms |
| Editor typing | 100 MB stress SQL file | p95 ≤50 ms with expensive features degraded explicitly, never main-thread parse |
| Completion | Warm metadata/local syntax candidate list | p95 ≤100 ms; stale result cancellation ≤50 ms |
| Find | 100 MB SQL file | first result ≤300 ms, cancellable incremental scan |
| Grid first paint | First 200-row result page/≤50 visible columns | p95 ≤300 ms after schema/first chunk arrives |
| Grid scroll | 1M-row logical result, bounded resident pages | ≥55 fps p95 during steady scroll; no repeated >33 ms frames |
| Grid theme change | Update visible cells only | p95 ≤100 ms; selection/scroll/pending edits unchanged |
| Filter/sort intent | UI acknowledgment and cancellable request start | ≤100 ms; server completion reported separately |
| Workspace save | 20 tabs including 10 MB total drafts | UI stall ≤50 ms; atomic completion p95 ≤1 s |

### 3.1 M0 grid measurement protocol

DF-M0-004 freezes the following protocol before its prototype is measured. A
future budget change requires new evidence; the spike must not select a more
favorable interpretation after seeing a result.

- Run a visible, unoccluded window on a display fixed at 60.00 Hz. Record the
  viewport, scaling, display connection and any mirroring. The `≥55 fps p95`
  gate means a p95 presented-frame interval of at most `1000 / 55 = 18.18 ms`.
  No more than 1% of presented intervals may exceed 33.33 ms, and two such
  intervals may not be consecutive.
- A Core Animation/display presentation instrument is the evidence source for
  a presented-frame claim. Display-link callbacks, scroll-step duration,
  `layoutSubtreeIfNeeded`, drawing callbacks and signposts are useful diagnostic
  proxies, but must be reported as proxies rather than FPS or presentation.
- BF-02 vertical scrolling uses 1M logical rows, a 200-row page, a 24-point row
  height and deterministic 10-second down/up sweeps at 2,400 points/second from
  start, midpoint and near-end anchors. Re-anchoring by stable row identity is
  outside the measured interval. The run is repeated with 10M logical rows to
  prove that logical cardinality does not materialize rows or grow the cache.
  The same presented-frame gate applies to both cardinalities.
- BF-03 uses 500 columns by 100k logical rows, three 120-point frozen columns,
  deterministic 80/120/180-point non-frozen widths and five selected text
  columns whose generated payload averages 10 KiB. Its 10-second horizontal
  forward/back scroll runs at 2,400 points/second and uses the same 18.18/33.33 ms
  presented-frame gate. Column resize and reorder are measured separately and
  must preserve row/column identity, selection, scroll anchor and pending
  edits.
- Grid first paint starts immediately before a ready schema and first 200-row
  chunk are applied to an otherwise cold grid, and ends at the first presented
  frame containing those cells. Use at most 50 non-hidden result columns and
  report their count and widths. Forced layout without a presented frame is a
  separately named first-layout proxy and cannot satisfy the p95 ≤300 ms gate.
- Theme timing starts before changing the palette version and ends at the first
  presented frame in which every visible cell uses the new resolved style.
  The data source and page cache are not reloaded. The p95 ≤100 ms gate also
  requires unchanged stable selection, scroll anchor and pending-edit keys.
- Incremental grid RSS is the peak physical footprint minus an empty visible
  harness after a five-second steady state, measured during page eviction,
  vertical/horizontal scrolling, theme changes and deferred-value access. The
  default cache has an item ceiling of five 200-row pages and a 64 MiB byte
  ceiling; it may hold fewer than five pages when the byte ceiling wins. At
  most one additional 1,000-row/4 MiB synthetic fetch chunk may be in flight.
  The separate pending-edit overlay has its own 10,000-cell/16 MiB ceilings and
  rejects further admission without discarding or applying an existing edit.
  Both 1M and 10M runs must remain ≤150 MiB incremental RSS, and their peaks
  must differ by no more than 8 MiB to support the cardinality-independent
  claim.
- Generated 1/10/100 MiB JSON/BLOB cells retain only type, logical length,
  locator and bounded preview metadata. The spike must never allocate the
  declared payload; preview remains at most 64 KiB and values over 1 MiB are
  deferred.
- Grid-fetch cancellation is exercised with a deterministic suspended
  synthetic producer. UI acknowledgement must be visible within 100 ms, no
  new chunk may be admitted 500 ms after the request, and terminal state must
  remain distinct from `cancelRequested`. This proves only the grid-side
  contract, not driver, network or FFI cancellation.
- Latency and frame scenarios use one unreported warm-up followed by 10
  measured samples. Publish every raw sample, median, nearest-rank p95
  (`sorted[ceil(0.95 * n) - 1]`) and worst. With 10 samples, p95 is the maximum.
  A coefficient of variation over 10% triggers environment diagnosis and a
  rerun rather than averaging the instability away.

DF-M0-004 records its disposition in
[ADR-0011](adr/0011-m0-grid-disposition.md) and the
[grid evidence report](reports/DF-M0-004-appkit-grid-evidence.md). The
`NSTableView` spike's forced-layout/display and scroll-step values are
diagnostic proxies, not presented frames. Its BF-03 renderer and unified
accessibility contract failed, so none of the presentation gates above is
waived or reinterpreted for the replacement renderer.

Automated accessibility inspection must verify table/row/cell/header roles,
stable row and column counts, selection, loading, SQL `NULL`, deferred and
modified descriptions. Manual VoiceOver navigation remains a separate gate;
metadata assertions alone are never reported as a VoiceOver pass.
Default text/background pairs use WCAG relative luminance and a 4.5:1 minimum
for ordinary grid text. A lower user-defined pair produces a visible and
accessible warning; color is still supplemented by icon/text/tooltip traits.

DF-M0-009 adds a static focus/appearance/resize/localization test contract in
the [wireframe review](reports/DF-M0-009-wireframe-accessibility-review.md).
It records no timing, contrast or frame measurement. The launch, cancel,
editor/grid, 4.5:1, minimum-machine and manual VoiceOver budgets above remain
unchanged and executable-release-gated.

## 4. Memory and bounded-resource budgets

| Resource | MVP budget/policy |
| --- | --- |
| Idle app, one empty window | Target ≤180 MB RSS on minimum machine after steady state; investigate >220 MB |
| One 1M-row streamed result | Incremental app RSS attributable to result ≤150 MB with default 5-page cache; independent of total row count |
| Ten result tabs | Global result cache ≤512 MB by default with LRU/visibility priority and user-visible eviction/reload semantics |
| Default result page | 200 rows; configurable 50–2,000 within byte cap |
| Result chunk | ≤1,000 rows and ≤4 MiB encoded, whichever first; oversized value deferred/truncated metadata |
| Swift/Rust result channel | Capacity ≤4 chunks per execution initially; producer blocks/yields under backpressure |
| Metadata cache | Global ≤128 MB and per-connection ≤32 MB initial target; lazy and invalidated by scope/TTL/events |
| Completion index | Per-connection ≤64 MB initial target with bounded object/column counts and LRU |
| Diagnostics/audit/history | Diagnostic logs: earlier of 7 days/50 MiB; dangerous-operation audit: 90 days/50 MiB; query history is separate with its own reviewed ceiling. All are configurable downward/delete-all. |
| Background jobs | Bounded worker count; proposed 2 data-heavy jobs and 4 lightweight operations globally, per-connection limits apply |
| Connection pools | Default max 4 per interactive profile, lower for SQLite; transaction-pinned sessions excluded from reuse |
| Large BLOB/text | Do not load >1 MiB cell by default; preview prefix ≤64 KiB; explicit stream/view/export |
| Queues/caches | Every instance documents owner, item+byte limit, eviction/invalidation, lifetime and thread contract |

Numbers are starting hypotheses. M0 spikes may lower them; raising them requires measurements on the 16 GB reference machine and a safety review.

## 5. Throughput and long-operation budgets

Throughput depends on server/network/disk, so report client overhead, end-to-end throughput and bottleneck separately.

| Operation | Fixture | Target |
| --- | --- | --- |
| Query streaming | 10M narrow rows from local PostgreSQL | Sustain ≥100k rows/s or ≥100 MiB/s when server permits; bounded RSS; cancel responsive ≤500 ms request propagation |
| CSV export | 10 GB generated typed stream to fast local SSD | ≥150 MiB/s client pipeline target; RSS increase ≤128 MB; atomic/marked partial behavior |
| CSV import | 10 GB local file to disposable PostgreSQL | ≥75 MiB/s when server permits; bounded RSS; error policy/checkpoints measured |
| Cross-engine transfer | 100 GB generated source with 100 ms RTT target | No fixed end-to-end minimum before spike; pipeline utilization ≥70%, bounded queues, exact partial/checkpoint report |
| Schema introspection | 100k objects / 1M columns synthetic catalog | First useful page ≤1 s; full cancellable background index target ≤60 s and ≤256 MB incremental RSS |
| Schema diff | 50k normalized objects, 10% changes | p95 ≤10 s; incremental RSS ≤512 MB; deterministic output |
| Data diff | 100M keyed rows synthetic, remote latency fixture | Streaming/checkpoint design; no full materialization; throughput baseline established per adapter in M4 |
| ER layout | 500 tables interactive; 5,000 stress | 500-table initial layout ≤2 s and pan/zoom ≥55 fps; 5,000-table overview ≤15 s/level-of-detail mode |
| Backup/restore | Official tool fixture | Client overhead ≤5%; progress update ≤1 s cadence; cancellation consequence reported |

Do not trade validation, escaping, encryption, transaction boundaries or verification for headline throughput.

## 6. Benchmark datasets

All datasets are synthetic, deterministic, versioned by generator/checksum and contain no customer data.

### BF-01 Large SQL

- 10 MB and 100 MB files;
- mixed PostgreSQL/MySQL syntax, Unicode identifiers, long lines, comments, dollar/procedural bodies, errors, 100k statements;
- edit at start/middle/end, multi-cursor, highlighting, formatting, find and completion cancellation.

### BF-02 Million-row grid

- 1M and 10M logical rows;
- integers, exact decimals, text, bool, dates/timestamps/time zones, UUID, JSON, binary metadata, enums, arrays, spatial descriptor and NULL/empty/not-loaded distinctions;
- stable keys, concurrent updates and pending edits across page eviction.

### BF-03 Wide and large-cell grid

- 500 columns × 100k rows;
- 10 KB average text in selected columns;
- 1 MiB, 10 MiB and 100 MiB deferred JSON/BLOB cells;
- horizontal/frozen column scroll, resize/reorder and VoiceOver sampling.

### BF-04 Large schema

- 10k databases/schemas/namespaces, 100k objects, 1M columns/constraints/index relations;
- deep hierarchy, limited-privilege gaps, refresh churn and object search.

### BF-05 Diff and model

- 50k schema objects with deterministic adds/removes/modifications/dependencies/rename candidates/cycles;
- relational models of 500 and 5,000 tables with dense/sparse relationships.

### BF-06 Import/export hostile and bulk

- 10 GB CSV/TSV/JSON/XML/XLSX generated streams;
- variable-width rows, Unicode/encoding boundaries, formula prefixes, malformed rows, deep nesting, compression bombs and path traversal cases within test isolation.

### BF-07 Network and server behavior

- RTT 0/20/100/300 ms, bandwidth 10/100/1,000 Mbps, packet loss 0/1/5%, half-close/interruption;
- slow query, slow row producer, malicious advertised lengths, cancellation race and tunnel teardown.

## 7. Component design requirements

### 7.1 Result stream and grid

- Producer never allocates based solely on an untrusted server length without a checked maximum.
- Backpressure travels through FFI to driver polling.
- Page cache keys use result/execution identity and stable row offsets/keys; cache cannot own pending edits.
- Theme cache stores resolved style tokens by palette/type/trait, not per-row duplicate objects; theme invalidation touches visible cells/style cache.
- Selection and scroll state store stable logical identity; evicted pages show loading rather than stale data.

### 7.2 Object tree and completion

- Lazy load one scope with cancellation and deduplicate concurrent requests.
- Cache owner is connection metadata service; scope invalidates on refresh/DDL/session context.
- Completion has a bounded normalized index and can omit low-priority objects explicitly rather than exhaust memory.

### 7.3 Editor

- Layout/highlighting/parsing is viewport/incremental; full parse/format is explicit and cancellable.
- Debounce/coalesce background analysis without delaying keystroke rendering.
- Large-file mode clearly reduces folding/semantic completion when budgets require it while preserving editing/save/recovery.

### 7.4 Pipelines

- Fixed bounded stages for read/decode/map/encode/write/verify; no unbounded fan-out.
- Report progress using bytes and rows where known; unknown totals stay indeterminate.
- Checkpoints flush only at documented safe boundaries; cancellation stops new work and drains/rolls back according to policy.

## 8. Cancellation budgets

| Situation | Visible acknowledgment | Propagation/terminal target |
| --- | --- | --- |
| Editor analysis/completion | ≤50 ms | worker stops ≤250 ms |
| Metadata/grid fetch | ≤100 ms | no new chunks ≤500 ms plus driver/network limitation |
| Query execution | ≤100 ms | adapter sends cancel ≤250 ms; terminal truth may be racy and is reported |
| Import/export/transfer/diff | ≤100 ms | stages stop accepting work ≤500 ms; safe checkpoint/cleanup duration reported |
| Native backup/restore tool | ≤100 ms | graceful signal target ≤1 s, escalation only by documented engine-safe policy |

The app must remain responsive while waiting. It never turns “cancel requested” into “cancelled” without terminal evidence.

## 9. Cache inventory contract

Before introducing a cache, its design record/code documentation must specify:

- owner and key identity;
- item and byte ceiling;
- admission and eviction algorithm;
- invalidation triggers and TTL;
- persistence or process-only lifetime;
- sensitive-data classification and redaction/deletion behavior;
- actor/lock/thread-safety contract;
- behavior on memory pressure;
- hit/miss/eviction metrics that contain no user data;
- tests for stale data, limit enforcement and concurrent access.

Unbounded memoization, global mutable dictionaries and “cache forever until disconnect” are rejected.

## 10. Regression gates

- Safety: any unbounded growth, main-thread DB/file I/O, cancellation deadlock or wrong-row/state issue blocks immediately.
- Absolute: release-blocking metric over its target fails the milestone exit unless a reviewed product decision changes the budget.
- Relative: >10% p95 latency/throughput/RSS regression from accepted baseline requires performance-owner review and explanation.
- Variance: coefficient of variation >10% triggers rerun/environment diagnosis; do not average away instability.
- Leaks: monotonic RSS/handle/task/connection growth in an 8-hour soak blocks.
- Claims: publish measured result with fixture/hardware/build; “fast” or “handles millions” without evidence is prohibited.

## 11. Milestone performance reviews

| Milestone | Required evidence |
| --- | --- |
| M0 | Editor, grid, C ABI streaming/cancel, signed shell size/build time baselines |
| M1 | Launch, restoration, Keychain/persistence/log retention and idle RSS |
| M2 | PostgreSQL connect/metadata/query/grid/edit/cancel/export under named fixtures |
| M3 | Per-engine deltas, pool/connection matrix and cross-database UX memory |
| M4 | Import/export/transfer/diff/backup streaming, checkpoint and large-data budgets |
| M5 | ER layout/monitoring long-run and execution-plan rendering |
| M6 | Additional engine protocol/type/model-specific baselines |
| M7 | Job concurrency, helper idle/active RSS, schedule/credential/tunnel soak |

## 12. Open measurements

- Define an editor-only incremental RSS ceiling before the next visible-host
  BF-01 run; the DF-M0-003 whole-process 10/100 MiB RSS baselines cannot be
  graded retroactively against an invented threshold.
- Measure SQL editor input event to Core Animation presented frame on the
  M1/16 GiB floor. Hidden-window forced local layout is only a proxy.
- Benchmark the ADR-0011 bounded custom native renderer against BF-02/BF-03 with row-and-column object caps, one logical accessibility table and true presented-frame evidence; the rejected `NSTableView` composition is not a baseline to promote.
- Select actual FFI chunk encoding and measure copy/decoding cost.
- Establish per-driver fetch/cursor/batch controls and cancellation latency.
- Measure Keychain prompt/retrieval and metadata migration at large history sizes.
- Set signed app/dylib/updater/helper size and build-time budgets after the M0 shell spike.
- Define energy-impact budgets for monitoring/background jobs before M5/M7.
- Calibrate defaults on an 8 GB machine only if product support research proposes one; current floor is 16 GB.
