# DF-M0-004 — AppKit typed-grid feasibility evidence

Status: complete as a disposable feasibility spike; disposition:
**REJECT THE FULL-GRID `NSTableView` COMPOSITION; SELECT A BOUNDED CUSTOM
NATIVE TWO-DIMENSIONAL RENDERER FOR THE NEXT PLANNING EVALUATION**

Evidence date: 2026-07-30

Evidence source commit: `7acdec023b1debab1daf4af354f8b9968ee9f32b`

## 1. Decision question and bounded scope

This spike asks whether a view-based `NSTableView` composition can present the
typed BF-02 million-row and BF-03 wide-column fixtures with bounded resources,
stable edit identity, frozen columns, visible-only theme work and one native
accessibility table.

The artifact is a standalone Swift/AppKit package. Its data is deterministic
and formula-generated. It has no database, network, database driver, FFI,
Keychain, credential, file import, query execution, SQL generation/write,
transaction or path that applies a pending edit. It is not a product module and
does not copy source, assets, wording, appearance or private behavior from a
commercial database product.

## 2. Evidence identity and environment

| Item | Recorded value |
| --- | --- |
| Source commit | `7acdec023b1debab1daf4af354f8b9968ee9f32b` |
| Host | Mac15,3; Apple M3; arm64; 8 logical CPUs; 25,769,803,776 bytes RAM |
| OS | macOS 26.5.2, build 25F84 |
| Xcode | 26.0.1, build 17A400 |
| Swift | Apple Swift 6.2 (`swiftlang-6.2.0.19.9`, `clang-1700.3.19.1`) |
| Package target | macOS 14.0, Swift 6 language mode, strict concurrency |
| Profile binary | arm64 Release; SHA-256 `15c12f881b58f495086f9caee2172c7bd77e47a9473820deaae061107a9c8012` |
| Visible harness | 1,280×800-point accessory window |
| Display | 1,920×1,080 points at 2× and 60 Hz; mirrored Virtual 16:9 ↔ DELL |
| Sampling | One unreported warm-up + 10 samples; 10-second scripted scroll runs |
| Post-run power/thermal snapshot | AC power, battery charged; `pmset` recorded no thermal/performance warning level |
| Storage | Pre-run free space was not captured; 383 GiB free after profiling and before trace cleanup |

This is a developer host with 24 GiB RAM and a newer OS, not the proposed Apple
M1/16 GiB/macOS 14 release floor. The window was ordered visible, but the
harness does not prove that it remained unoccluded. Mirroring also means that
any Core Animation trace from this host is diagnostic rather than
release-floor presentation evidence. No serial number, hardware UUID,
provisioning identifier or trace device UUID is retained.

## 3. Fixture identity

The revision-1 generator computes schema, rows and cells on demand. Its
checksum samples exactly 128 rows and is an FNV-1a-64 grid manifest checksum,
not a hash of a materialized logical dataset.

| Fixture | Logical dimensions | Selected payload contract | Sampled cells | Checksum |
| --- | ---: | --- | ---: | --- |
| BF-02 | 1,000,000 × 21 | normalized typed cells and stable identities | 2,688 | `3cd9aebb3ca2b6d4` |
| BF-02 | 10,000,000 × 21 | same generator, independent cardinality process | 2,688 | `91f93c788062febb` |
| BF-03 | 100,000 × 500 | three frozen columns, five 10 KiB text columns, deferred 1/10/100 MiB values | 64,000 | `defefcc9c2bc88b6` |

The deferred descriptors retain type, logical byte length, a synthetic locator
and at most a 64 KiB preview. The declared 1/10/100 MiB payloads are never
allocated. SQL `NULL`, not loaded, empty text and empty binary use distinct
typed states.

## 4. Harness and frozen measurement contract

The renderer uses a primary view-based `NSTableView` plus a synchronized frozen
projection. AppKit state is `@MainActor`. A formula-backed page service owns a
five-item/64 MiB LRU cache; a separate pending-edit overlay admits at most
10,000 cells/16 MiB and rejects overflow without eviction or apply. Stable
result, row, column and cell IDs do not depend on view reuse or column order.

BF-02 scrolls vertically from start, midpoint and near-end. BF-03 scrolls
horizontally with three frozen columns. Each scenario has one warm-up followed
by 10 measured 10-second runs. First-layout and theme measurements also have
one warm-up plus 10 samples. Median, nearest-rank p95, worst, coefficient of
variation and every raw value are retained in the sanitized JSON evidence.

The first-layout, theme-layout and scroll-step timings are forced-layout/display
diagnostic proxies. They do not observe Core Animation presentation and
therefore do not establish first paint, theme-to-presented-frame latency, FPS,
presented-frame p95, hitch incidence or consecutive-hitch gates. A numerical
proxy below a presentation target is not a pass.

Mach `phys_footprint` records the harness baseline and peak during each process.
`/usr/bin/time -l` maximum RSS covers the complete process and is reported
separately. Neither is converted into the other.

Automated metadata and direct AppKit API checks do not establish VoiceOver
behavior. Fixture row/column counts do not establish the accessibility tree's
actual column coverage.

## 5. Exact commands and validation results

The final uninstrumented command ran from the clean source commit:

```sh
cd spikes/nstableview-grid
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh
```

The script records the toolchain, then runs:

```sh
xcrun swift-format lint --strict --recursive Package.swift Sources Tests

xcrun swift build --scratch-path "$scratch/debug" \
  -Xswiftc -warnings-as-errors

xcrun swift test --scratch-path "$scratch/tests" \
  --enable-xctest --disable-swift-testing \
  -Xswiftc -warnings-as-errors

xcodebuild \
  -scheme NSTableViewGridSpike-Package \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$scratch/DerivedData" \
  SUPPORTS_MACCATALYST=NO build test

xcrun swift build --configuration release \
  --scratch-path "$scratch/release" \
  -Xswiftc -warnings-as-errors

/usr/bin/time -l "$scratch/release/release/grid-evidence" \
  --fixture bf02 --rows 1000000 --samples 10 --scroll-seconds 10 \
  --source-revision 7acdec023b1debab1daf4af354f8b9968ee9f32b

# Repeat with BF-02 10,000,000 and BF-03 100,000 rows.

# From the package directory
xcrun swift package show-dependencies --format json

# From the repository root; full invariant expression is retained in review
jq empty docs/reports/data/DF-M0-004/*.json
shasum -a 256 docs/reports/data/DF-M0-004/*.json

git grep -n -I -E \
  'AKIA[0-9A-Z]{16}|BEGIN ([A-Z ]+ )?PRIVATE KEY|password[[:space:]]*[:=]|api[_-]?key[[:space:]]*[:=]|access[_-]?token[[:space:]]*[:=]|refresh[_-]?token[[:space:]]*[:=]' \
  7acdec0 -- spikes/nstableview-grid
```

| Gate | Result |
| --- | --- |
| Strict `swift-format` lint | Pass |
| Debug SwiftPM build, warnings as errors | Pass |
| SwiftPM XCTest | Pass: 41 tests, 0 failures |
| Native macOS Xcode package build/test | Pass: 41 tests, 0 failures |
| Release build, warnings as errors | Pass |
| BF-02 1M evidence process | Exit 0; schema-1 JSON parsed |
| BF-02 10M evidence process | Exit 0; schema-1 JSON parsed |
| BF-03 evidence process | Exit 0 after 1,353.64 seconds; schema-1 JSON parsed |
| Swift package dependency inventory | Empty; no third-party dependency |
| Sanitized raw JSON schema/count/invariant validation | Pass for all three files |
| Targeted source/report secret-pattern scan | No matches; `gitleaks` and `trufflehog` unavailable |

The Xcode run emitted non-fatal host service diagnostics involving
`com.apple.linkd.autoShortcut`; the test operation still succeeded. This is
native AppKit evidence; Mac Catalyst was disabled.

## 6. BF-02 evidence

### 6.1 Layout/theme proxies and cancellation

All values are milliseconds. They are diagnostic proxies except for the
synthetic actor cancellation intervals.

| Fixture / metric | Median | p95 | Worst | CV | Interpretation |
| --- | ---: | ---: | ---: | ---: | --- |
| 1M first forced layout | 36.534 | 37.687 | 37.687 | 2.91% | Numeric proxy below 300 ms; first presented frame not established |
| 1M visible theme forced layout | 13.595 | 14.209 | 14.209 | 2.65% | Numeric proxy below 100 ms; theme presentation not established |
| 1M cancel acknowledgement | 0.026 | 0.043 | 0.043 | 40.91% | All synthetic acknowledgements below 100 ms; sub-millisecond CV is noisy |
| 1M terminal after producer release | 0.081 | 0.187 | 0.187 | 43.98% | Every late synthetic value suppressed |
| 10M first forced layout | 35.825 | 40.194 | 40.194 | 4.55% | Presented frame not established |
| 10M visible theme forced layout | 12.668 | 14.164 | 14.164 | 3.85% | Theme presentation not established |
| 10M cancel acknowledgement | 0.033 | 0.042 | 0.042 | 34.99% | Grid-side synthetic contract only; every late value suppressed |

The cancellation fixture holds a structured producer behind a deterministic
barrier, requests cancellation, waits 510 ms before release and verifies that
the late value cannot become a result. It proves neither UI paint nor database
driver, network or FFI cancellation.

### 6.2 Scroll-step diagnostic proxies

The table reports the range across ten run summaries at each anchor. It does
not report frame intervals.

| Cardinality / anchor | Run median range | Run p95 range | Worst step | Steps >18.18 ms | Steps >33.33 ms | Within-run CV range |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1M start | 9.463–10.400 | 14.773–16.469 | 163.210 | 137 | 50 | 81.80–92.71% |
| 1M midpoint | 9.731–10.777 | 15.871–17.708 | 159.551 | 227 | 71 | 90.43–103.64% |
| 1M near-end | 9.500–10.282 | 15.102–16.656 | 204.444 | 138 | 50 | 90.42–102.32% |
| 10M start | 9.419–10.082 | 14.613–15.734 | 155.626 | 152 | 50 | 83.39–94.22% |
| 10M midpoint | 9.774–10.783 | 15.819–18.099 | 166.451 | 214 | 70 | 88.61–102.06% |
| 10M near-end | 9.370–10.189 | 14.882–17.025 | 188.188 | 138 | 52 | 89.58–101.97% |

The 1M within-run CV exceeds 10% because the workload repeatedly alternates
ordinary steps with cache/page/view work and large stalls. The ten independent
runs reproduce this non-stationary behavior: CV across the ten run-level p95
values is only 2.86–3.49% for 1M and 2.29–3.97% for 10M, depending on anchor.
The variation is therefore reported as renderer diagnostic failure evidence
rather than averaged away, attributed to an unstable host or relabelled as
frame performance.

### 6.3 Resource inventory

| Metric | BF-02 1M | BF-02 10M | Contract |
| --- | ---: | ---: | --- |
| Cache entries | 5 | 5 | ≤5 |
| Cache bytes | 1,762,444 | 1,766,252 | ≤64 MiB |
| Cache evictions | 115 | 115 | Churn expected; pending edits independent |
| Created cell views | 756 | 756 | Diagnostic inventory |
| Peak geometrically visible cells | 350 | 350 | Viewport diagnostic |
| Pending edit cells | 1 | 1 | Separate overlay |
| Blank visible-harness `phys_footprint` | 15,680,232 | 15,663,848 | Per-process baseline |
| Peak `phys_footprint` | 282,133,632 | 280,216,728 | Per-process peak |
| Incremental peak | 266,453,400 (254.11 MiB) | 264,552,880 (252.30 MiB) | **Fail:** each ≤150 MiB; delta 1.81 MiB ≤8 MiB |
| `/usr/bin/time` maximum RSS | 352,845,824 (336.50 MiB) | 376,193,024 (358.77 MiB) | Whole-process diagnostic, not `phys_footprint` |

The 1M and 10M processes exceed the 150 MiB incremental budget by 104.11 MiB
and 102.30 MiB respectively even though each final page cache retains only
about 1.68 MiB. Their incremental peaks differ by 1.81 MiB, which supports
cardinality independence but cannot turn two absolute memory failures into a
pass. The excess cannot be explained by logical-row materialization or final
cache ownership alone.

## 7. BF-03 wide-grid evidence

### 7.1 Renderer expansion and memory

| Metric | BF-03 result | Interpretation |
| --- | ---: | --- |
| Logical dimensions | 100,000 × 500 | Formula-generated; no row-cardinality array |
| Frozen / primary columns | 3 / 497 | Two physical table projections |
| Created cell views | 17,000 | `NSTableView` has no required column virtualization |
| Peak geometrically visible cells | 374 | Two-dimensional viewport denominator |
| Horizontal expansion ratio | 45.45× | Full wide-schema view graph versus geometry |
| Cache entries / bytes | 1 / 19,390,366 (18.49 MiB) | Bounded model-store inventory |
| Blank / peak `phys_footprint` | 15,745,768 / 2,129,398,328 | Per-process Mach measurements |
| Incremental `phys_footprint` | 2,113,652,560 (1.97 GiB) | **Fail:** 150 MiB developer-host target |
| Whole-process maximum RSS | 1,941,127,168 (1.81 GiB) | Separate `/usr/bin/time` diagnostic |
| `/usr/bin/time` peak memory footprint | 2,252,261,848 (2.10 GiB) | End-of-process diagnostic, separate from runner peak |

The raw `cellReuseWithinTwoTimesVisibleBudget` boolean is computed as
`peakAvailableCellViews > 0 && createdCellViews <= peakAvailableCellViews * 2`.
It checks creation after the cold-layout reset relative to the already
available view graph: BF-02 evaluates `756 <= 1,512` and BF-03 evaluates
`17,000 <= 34,000`. It is a steady-scroll allocation-churn diagnostic, not a
two-dimensional viewport bound. `peakGeometricallyVisibleCells` is used only
for `horizontalViewExpansionRatio`. The recorded `true` value therefore does
not offset 17,000 available views for 374 geometrically visible cells; the
45.45× expansion is the renderer feasibility result.

### 7.2 Layout, theme and horizontal-scroll proxies

| Metric | Median | p95 | Worst | CV / count |
| --- | ---: | ---: | ---: | ---: |
| First forced layout | 53.459 | 65.012 | 65.012 | 9.17% |
| Visible theme forced layout | 18.084 | 18.962 | 18.962 | 2.96% |
| Synthetic cancel acknowledgement | 0.014 | 0.073 | 0.073 | 75.21%; all late values suppressed |
| Horizontal run-summary median range | 36.379–38.312 | — | — | — |
| Horizontal run-summary p95 range | 44.042–49.797 | — | — | 10 runs |
| Worst horizontal step | — | — | 84.173 | — |
| Proxy steps >18.18 / >33.33 ms | — | — | — | 5,980 / 5,977 of 6,000 |
| Within-run CV range | — | — | — | 10.68–15.49% |

Frozen scrolling remains a direct coordinate-synchronization smoke only. No
proxy value is called FPS or a presented-frame result.

The BF-03 evidence process required 1,353.64 seconds for a nominal set of
10-second scripted runs and consumed 1,325.02 user CPU seconds. This is direct
evidence that the composition is unsuitable, even before the missing
presented-frame and release-floor gates are considered. Every within-run CV is
above 10%, but CV across the ten run-level p95 values is 4.49%; repeated runs
therefore reproduce the wide-view workload rather than showing random host
noise.

### 7.3 Accessibility failure

The BF-03 frozen table is ignored in the accessibility tree while the primary
table owns only 497 non-frozen columns. The snapshot's `logicalColumnCount` is
fixture metadata, not an inspection of 500 exposed accessibility columns. The
help text claiming that the primary table includes every logical column is
therefore inaccurate for BF-03.

The one-logical-table contract is **failed**, not merely untested. Manual
VoiceOver remains separately not established. Direct first-responder and
header/value-description smoke cannot convert the split tree into a pass.

## 8. Instruments, leaks and diagnostic limits

All profiling used the exact release binary rebuilt from the source revision
above. To avoid repeating a 22-minute BF-03 process under instrumentation, the
diagnostic runners used `--scroll-seconds 0.1`; the final BF-03 Animation
Hitches attempt used `0.01`. They are not the frozen 10-second protocol.

The BF-02 Animation Hitches smoke target exited 0 after 31.252 seconds; the
recorder exited 0. It captured only four displayed-surface rows for the target,
with reported CPU-to-display latencies of 321.22, 81.30, 39.88 and 42.87 ms.
Its `hitches-summary` and `potential-hangs` exports contained schemas but no
event rows. That does not prove a clean frame sequence: the short smoke did not
produce continuous target presentations, the display was mirrored, and
unoccluded state was not established. The recorder also expanded to a
temporary 20 GiB trace; a stop request protected disk space and the command
then finalized a roughly 521 MiB trace.

A still-shorter BF-03 Animation Hitches target completed, but `xctrace` exited
1 when trace finalization expanded to 33 GiB. That trace was deleted
immediately and contributes no frame evidence. Repeating it would consume
resources without changing the already decisive renderer, memory and
accessibility failures.

Short BF-02/BF-03 Time Profiler traces completed against the reduced workload:
both recorder and target exited 0, after 28.199 and 57.510 seconds respectively.
Across 14,459 BF-02 CPU samples, `scroll(toLogicalRow:)` accounted for 5,177 ms
inclusive and `tableView(_:viewFor:row:)` for 2,313 ms. Across 46,746 BF-03
samples, `tableView(_:viewFor:row:)` accounted for 18,837 ms,
`availableCellViewCount(in:)` for 13,037 ms, `NSTableCellView` construction for
4,134 ms and wide-text creation for about 1,179 ms. This reinforces that the
decisive BF-03 cost is the AppKit view graph and cell-view traversal, not
logical-row materialization. The traces remain root-cause diagnostics only;
initialization, fixture-checksum work and the reduced scroll interval prevent a
product timing attribution.

Allocations traces were also diagnostic and unusually large: BF-02 exited 0
after 62.296 seconds with 212,959,544 bytes incremental footprint under
instrumentation; BF-03 exited 0 after 146.147 seconds with 2,248,411,080 bytes,
17,000 views and the same 45.45× expansion. The trace bundles were about 3.4
GiB and 5.9 GiB. CLI export exposed no allocation-summary table, so deeper
inspection would require Instruments GUI. The target JSONs completed, but the
trace volume and shortened workload are not an allocation-budget pass.

An `xctrace` Leaks-template attempt reached its 180.788-second limit before the
BF-02 target emitted JSON and produced a roughly 15 GiB transient trace. The
recorder exited 54; the target received `SIGKILL` and returned status 9. It is
recorded as unavailable evidence, not retried for BF-03. Separate isolated
commands were therefore used for BF-02 and BF-03:

```sh
/usr/bin/leaks --atExit -- \
  grid-evidence \
  --fixture bf02 --rows 1000000 --samples 10 --scroll-seconds 0.1 \
  --source-revision 7acdec023b1debab1daf4af354f8b9968ee9f32b

# Repeat with --fixture bf03 --rows 100000.
```

Both `leaks` commands exited 1. BF-02 reported 604,897 allocated nodes, 288
leaked nodes and 18,816 leaked bytes. BF-03 reported 11,788,300 allocated nodes,
283 leaked nodes and 18,560 leaked bytes, with 2.3 GiB final/2.8 GiB peak
physical footprint under leak instrumentation. All leak roots in both runs
were three `NSXPCConnection` cycles in AppIntents/LinkServices for the
unavailable `com.apple.linkd.autoShortcut` service. No `GridSpike`,
`VirtualizedGrid`, `GridPage`, `FixtureGenerator` or `grid-evidence` symbol
appeared in either leak-root section. This is residual framework evidence, not
“zero leaks,” and it does not cover repeated open/close or a long-running app.

Trace bundles are transient because they contain local process/device metadata.
Only sanitized commands, exit status and observations are retained. A short
diagnostic trace cannot establish unoccluded presentation, the M1/macOS 14
floor, an eight-hour soak or absence of UI hangs/leaks.

## 9. Functional, safety and security evidence

Positive evidence from both 41-test suites includes:

- deterministic BF-02/BF-03 dimensions, typed values, checksums and stable
  result/row/column/cell identity;
- LRU item/byte eviction, concurrent admission and memory-pressure behavior;
- a separately bounded pending-edit overlay that rejects overflow and retains
  existing edits through cache churn, reorder, theme and pressure;
- page row/byte caps, stale-generation invalidation and synthetic cancellation;
- frozen vertical-coordinate/selection synchronization and column identity
  across resize/reorder;
- normalized Light/Dark/High Contrast/Color Blind/Minimal style tokens,
  contrast checking and non-color traits; and
- deferred metadata remaining unmaterialized.

The appearance tests validate token resolution and visible invalidation; they
do not replace snapshot/UI inspection on Light/Dark displays. The accessibility
tests intentionally detect the BF-03 split-table failure and do not claim
VoiceOver success. Unit configuration behavior does not prove a real streamed
driver/FFI in-flight chunk contract.

No database connection, query, write, retry, transaction or result set exists,
so this spike supplies no database-operation safety evidence. There is no
credential, Keychain, connection string, row-data log, clipboard, persisted
profile or environment-secret output. All values are deterministic synthetic
data and pending edits can never be applied.

## 10. Acceptance mapping

| DF-M0-004 requirement | Disposition |
| --- | --- |
| Deterministic BF-02 1M/10M and BF-03 500×100k without row materialization | Met |
| Normalized typed states and deferred 1/10/100 MiB descriptors | Met in model/tests |
| Five-page/64 MiB cache and separate 10k-cell/16 MiB edit overlay | Met in model/tests and inventories |
| Stable selection/scroll/edit/column identity across exercised churn | Met in synthetic harness |
| Grid-side cancellation acknowledgement and late-value suppression | Met for synthetic coordinator only; driver/network/FFI not established |
| Incremental `phys_footprint` ≤150 MiB and 1M/10M delta ≤8 MiB | **Failed:** 254.11/252.30 MiB; cardinality delta alone passes at 1.81 MiB |
| First presented frame ≤300 ms | Not established; forced-layout proxy only |
| Theme presented frame ≤100 ms with unchanged state | State met; presentation not established |
| Presented-frame p95/hitch gates for BF-02/BF-03 | Not established; step proxies only |
| BF-03 bounded row-and-column renderer | **Failed**; wide physical view graph expands beyond viewport |
| One logical table and manual VoiceOver | **Failed** unified BF-03 tree; manual VoiceOver not established |
| Light/Dark/contrast/non-color runtime UX | Token/trait tests met; snapshot/manual runtime evidence not established |
| M1/16 GiB/macOS 14 floor | Not run |
| Leak/repeated open-close/eight-hour soak | BF-02/BF-03 reduced framework-residual leak smoke recorded; repeated open/close and eight-hour soak not run |
| Prototype disposal | Met by commit `c775b8e304c71719cf066e4b8cf37c9c36ae6173` |

The backlog criterion permits an accepted fallback decision. It does not permit
lowering the memory, presentation or accessibility contract.

## 11. Disposition and production re-entry criteria

**Reject the current full-grid `NSTableView` plus synchronized frozen-table
composition. Select a bounded custom native two-dimensional renderer as the
next planning candidate. Keep production implementation closed.**

The replacement must virtualize both rows and columns, cap retained rendering
objects/bytes independently of logical dimensions and expose one unified
accessibility table across frozen and scrollable regions. Page/cache/fetch,
normalized values, stable identity, selection, pending edits and theme
resolution remain renderer-independent contracts.

Before DF-M2-007 can enter implementation review, the replacement requires:

1. BF-02/BF-03 release runs on Apple M1/16 GiB/macOS 14.
2. True Core Animation presented-frame evidence for cold first paint,
   vertical/horizontal scroll and theme change.
3. ≤150 MiB incremental footprint, ≤8 MiB 1M/10M delta and a hard
   row-and-column rendering-object inventory.
4. One automated logical accessibility hierarchy plus documented manual
   VoiceOver, keyboard, focus, resize and frozen-region navigation.
5. Light/Dark/contrast/non-color snapshots and runtime checks.
6. Exact selection, scroll and pending-edit preservation under fetch, eviction,
   reorder, theme, pressure and cancellation.
7. Leak/repeated-open-close diagnostics and an eight-hour soak.

Any wrong-row or lost-edit result blocks the component regardless of speed.
The complete `spikes/nstableview-grid` directory was removed in disposal commit
`c775b8e304c71719cf066e4b8cf37c9c36ae6173` after this report, ADR-0011 and
sanitized raw evidence were committed. Future code must be rebuilt under
reviewed `ResultGrid`/`SharedUI` boundaries; the spike is not promoted
wholesale.

## 12. Durable raw evidence

Every raw timing sample required by the frozen protocol is retained as
sanitized, machine-readable JSON rather than summarized away:

- [`BF-02 1M raw evidence`](data/DF-M0-004/bf02-1000000.json)
- [`BF-02 10M raw evidence`](data/DF-M0-004/bf02-10000000.json)
- [`BF-03 raw evidence`](data/DF-M0-004/bf03-100000.json)

On 2026-08-01, review corrected only the explanatory accessibility note in the
two BF-02 files to match their no-frozen-column fields. Numeric measurements,
booleans, fixture identity and conclusions are unchanged; the byte/hash table
below identifies the corrected durable files.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `bf02-1000000.json` | 420,141 | `3112cc541c9d6a33ca0a95082388b5ed015b8792744e6a9e37c279d678e59a58` |
| `bf02-10000000.json` | 419,964 | `a0ef2bb33cf1de066cebf50c21c2df55d68417e352d2c56e312810133fb4d010` |
| `bf03-100000.json` | 146,754 | `7e941c722d18f32cbf3b8563ab6521151d1394d62febcc5292a011e3f60e328e` |

The JSON contains synthetic counts, timings, fixture hashes and coarse host
information only. It contains no path, username, serial number, credential,
SQL, row payload or customer data.

## 13. Primary platform references

- [Apple `NSTableView` documentation](https://developer.apple.com/documentation/appkit/nstableview)
- [Apple view-based table documentation](https://developer.apple.com/documentation/appkit/nstableview/using-a-table-view-as-a-view-based-table)
- [Apple accessibility for AppKit](https://developer.apple.com/documentation/appkit/accessibility-for-appkit)
- [Apple Instruments help](https://help.apple.com/instruments/mac/current/)
