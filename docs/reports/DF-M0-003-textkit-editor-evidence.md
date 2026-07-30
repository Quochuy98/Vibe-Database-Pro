# DF-M0-003 — TextKit 2 SQL editor feasibility evidence

Status: complete as a disposable feasibility spike; disposition:
**CONDITIONALLY RETAIN FOR PLANNING, DEFER PRODUCTION IMPLEMENTATION**

Evidence date: 2026-07-30

Evidence source commit: `130bd3a79e48bb2b029e1624132eeb5b241fde59`

## 1. Decision question and bounded scope

This spike asks whether an explicit `NSTextView`/TextKit 2 graph remains a
credible native SQL-editor candidate for large documents while keeping layout,
highlighting, find, cancellation and edit history bounded.

The artifact is a standalone AppKit/Swift package. It has no database, network,
FFI, file persistence, query execution, history, credential, customer data or
production module. It does not implement a full SQL parser, completion,
formatting, folding, multiple cursors or crash recovery. No source, asset,
wording or private protocol from a commercial database product was used.

## 2. Evidence identity and environment

| Item | Recorded value |
| --- | --- |
| Source commit | `130bd3a79e48bb2b029e1624132eeb5b241fde59` |
| Host | Mac15,3; Apple M3; arm64; 8 logical CPUs; 25,769,803,776 bytes RAM |
| OS | macOS 26.5.2, build 25F84 |
| Xcode | 26.0.1, build 17A400 |
| Swift | Apple Swift 6.2 (`swiftlang-6.2.0.19.9`, `clang-1700.3.19.1`) |
| Package target | macOS 14.0, Swift 6 language mode |
| Power/storage | AC power, battery charged; 473 GiB free before evidence run |
| Trace thermal state | Nominal for the complete Time Profiler interval |

This is a developer host with 24 GiB RAM and a newer OS, not the proposed
Apple M1/16 GiB/macOS 14.x release floor. Display configuration was not
captured, and the harness did not present a visible interactive editor. No
serial number, hardware UUID, provisioning identifier or trace device UUID is
retained in this report.

## 3. Fixture identity

The in-memory BF-01 revision-1 generator is deterministic and requires exactly
100,000 statements. It includes mixed PostgreSQL/MySQL-like syntax, Unicode
identifiers, long comments, dollar/procedural bodies and intentional errors.

| Fixture | Bytes | UTF-16 units | Lines | Statements | SHA-256 |
| --- | ---: | ---: | ---: | ---: | --- |
| BF-01 10 MiB | 10,485,760 | 10,210,760 | 101,045 | 100,000 | `b31912ef23f60bfbfa002626cbd17410d7923b1765e8f1907c0a86c2a8488e56` |
| BF-01 100 MiB | 104,857,600 | 104,582,600 | 123,889 | 100,000 | `f21ca93f425d02f5526b44b36ac2e9048bd1bf2e200d5a9b18665d50fdf88ffb` |

Generation took 152.337 ms and 1,205.950 ms respectively. Generation is a
single diagnostic measurement, not a sampled latency result.

## 4. Harness and measurement method

The harness builds `NSTextContentStorage` → `NSTextLayoutManager` →
`NSTextContainer` → `NSTextView` explicitly. A pre-construction observer watches
Apple's `didSwitchToNSLayoutManagerNotification`; ordinary evidence runs fail
if TextKit 1 appears. A debug-only positive control intentionally accesses the
legacy layout manager and proves that the observer detects the switch.

The design bounds:

- documents at 110 MiB, replacement payloads at 4 KiB and affected native
  ranges at 4,096 UTF-16 units;
- analysis input at 65,536 UTF-16 units and output at 1,024 keyword spans;
- find input at 115 Mi UTF-16 units, needles at 1,024 units and chunks at
  4 Mi UTF-16 units (hard configuration maximum 16 Mi);
- undo history at 100 levels, with UTF-8 byte accounting across native grouped
  edits, undo and redo;
- 100 MiB mode disables folding and semantic completion while retaining plain
  editing, bounded highlighting, find, selection, undo and accessibility
  metadata.

Each sampled metric has one unmeasured warm-up followed by ten measurements.
The report uses the arithmetic middle-pair median and nearest-rank p95. With ten
samples, nearest-rank p95 is the worst sample. Fixture/cache state and metric
definitions are unchanged between sizes.

`editAndForcedLocalLayout` measures synchronous edit API work plus forced local
TextKit 2 layout/display in a hidden window. It is a repeatable proxy, **not**
input-event-to-presented-frame paint. Cancellation is requested 1 ms after task
creation without a worker-start barrier. The measured interval ends when the
structured child terminates; it is not an Instruments signpost proof that a
worker was active at the request instant.

## 5. Exact commands and validation results

The working tree was clean at the source commit for the final runs.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcrun swift-format lint --strict --recursive Package.swift Sources Tests

xcrun swift test --configuration release \
  --scratch-path /tmp/dataforge-editor-swiftpm-release-130bd3a \
  -Xswiftc -warnings-as-errors

xcodebuild build test \
  -scheme TextKitEditorSpike-Package \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/dataforge-editor-xcodebuild-130bd3a \
  CODE_SIGNING_ALLOWED=NO SUPPORTS_MACCATALYST=NO

xcrun swift build --configuration release \
  --scratch-path /tmp/dataforge-editor-evidence-130bd3a \
  -Xswiftc -warnings-as-errors

/usr/bin/time -l \
  /tmp/dataforge-editor-evidence-130bd3a/release/TextKitEditorEvidence \
  --size 10 --samples 10

/usr/bin/time -l \
  /tmp/dataforge-editor-evidence-130bd3a/release/TextKitEditorEvidence \
  --size 100 --samples 10

xcrun xctrace record --template 'Allocations' \
  --output /tmp/df-m0-003-130bd3a-allocations.trace \
  --target-stdout /tmp/df-m0-003-130bd3a-allocations.json --no-prompt \
  --launch -- \
  /tmp/dataforge-editor-evidence-130bd3a/release/TextKitEditorEvidence \
  --size 100 --samples 10

xcrun xctrace record --template 'Time Profiler' \
  --output /tmp/df-m0-003-130bd3a-time-profiler.trace \
  --target-stdout /tmp/df-m0-003-130bd3a-time-profiler.out --no-prompt \
  --launch -- \
  /tmp/dataforge-editor-evidence-130bd3a/release/TextKitEditorEvidence \
  --size 100 --samples 10

/usr/bin/leaks --atExit -- \
  /tmp/dataforge-editor-evidence-130bd3a/release/TextKitEditorEvidence \
  --size 100 --samples 10

xcrun xctrace export \
  --input /tmp/df-m0-003-130bd3a-time-profiler.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]'
xcrun xctrace export \
  --input /tmp/df-m0-003-130bd3a-time-profiler.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hang-risks"]'
xcrun xctrace export \
  --input /tmp/df-m0-003-130bd3a-time-profiler.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="device-thermal-state-intervals"]'

git grep -n -I -E \
  'AKIA[0-9A-Z]{16}|BEGIN ([A-Z ]+ )?PRIVATE KEY|password[[:space:]]*[:=]|api[_-]?key[[:space:]]*[:=]|access[_-]?token[[:space:]]*[:=]|refresh[_-]?token[[:space:]]*[:=]' \
  130bd3a -- spikes/textkit-editor
```

| Gate | Result |
| --- | --- |
| Strict `swift-format` lint | Pass |
| SwiftPM release build/test, warnings as errors | Pass: 19 tests, 0 failures; debug-only fallback positive control excluded |
| Native macOS Xcode package build/test | Pass: 20 tests, 0 failures, including fallback positive control |
| Release evidence executables | Both exited 0; JSON schema 2 parsed successfully |
| Targeted secret-pattern scan of the source commit | No matches; `gitleaks`/`trufflehog` were not installed |

The Xcode run emitted non-fatal host-service diagnostics for an invalid display
identifier and unavailable `com.apple.linkd.autoShortcut`, plus AppIntents
metadata-extraction warnings. Tests still completed successfully. Mac Catalyst
was explicitly disabled; this is native AppKit evidence only.

## 6. Sampled latency results

All values are milliseconds and are from the uninstrumented release runs.

### 6.1 Load, viewport and edit proxy

| Fixture / metric | Median | p95 | Worst |
| --- | ---: | ---: | ---: |
| 10 MiB load | 12.356 | 13.873 | 13.873 |
| 10 MiB viewport start | 1.113 | 1.154 | 1.154 |
| 10 MiB viewport middle | 1.407 | 1.515 | 1.515 |
| 10 MiB viewport end | 0.700 | 0.729 | 0.729 |
| 10 MiB edit + forced local layout, start | 1.494 | 1.800 | 1.800 |
| 10 MiB edit + forced local layout, middle | 1.512 | 1.597 | 1.597 |
| 10 MiB edit + forced local layout, end | 1.113 | 1.143 | 1.143 |
| 100 MiB load | 71.508 | 81.289 | 81.289 |
| 100 MiB viewport start | 1.089 | 1.120 | 1.120 |
| 100 MiB viewport middle | 0.675 | 0.696 | 0.696 |
| 100 MiB viewport end | 0.687 | 0.734 | 0.734 |
| 100 MiB edit + forced local layout, start | 1.455 | 1.648 | 1.648 |
| 100 MiB edit + forced local layout, middle | 1.886 | 2.101 | 2.101 |
| 100 MiB edit + forced local layout, end | 1.113 | 1.133 | 1.133 |

The proxy p95 values are below the numerical 16.7 ms/50 ms targets, but the
actual BF-01 target is input-to-paint. Consequently this is positive headroom,
not a performance-budget pass.

### 6.2 Bounded analysis, decoration, find and history

| Fixture / metric | Median | p95 | Worst | Outcome |
| --- | ---: | ---: | ---: | --- |
| 10 MiB visible analysis | 0.285 | 4.490 | 4.490 | 32,768-unit snapshot; output cap reached |
| 10 MiB highlight + local layout | 4.365 | 4.478 | 4.478 | 1,024 spans applied |
| 10 MiB find middle | 7.837 | 8.024 | 8.024 | Exact UTF-16 location |
| 10 MiB find near end | 9.648 | 10.826 | 10.826 | Exact UTF-16 location |
| 10 MiB find absent | 9.977 | 14.735 | 14.735 | Correctly absent |
| 10 MiB undo | 0.355 | 0.373 | 0.373 | UTF-16 and UTF-8 restored |
| 10 MiB redo | 0.346 | 0.364 | 0.364 | UTF-16 and UTF-8 restored |
| 100 MiB visible analysis | 0.290 | 4.355 | 4.355 | 32,768-unit snapshot; output cap reached |
| 100 MiB highlight + local layout | 4.206 | 4.252 | 4.252 | 1,024 spans applied |
| 100 MiB find middle | 45.575 | 46.051 | 46.051 | Exact UTF-16 location |
| 100 MiB find near end | 96.659 | 97.823 | 97.823 | Exact UTF-16 location |
| 100 MiB find absent | 89.515 | 91.065 | 91.065 | Correctly absent |
| 100 MiB undo | 0.390 | 0.427 | 0.427 | UTF-16 and UTF-8 restored |
| 100 MiB redo | 0.347 | 0.385 | 0.385 | UTF-16 and UTF-8 restored |

The worst matching-result p95 is 10.826 ms at 10 MiB and 97.823 ms at
100 MiB, below the 300 ms developer-host target. The highlighter intentionally
stopped at 1,024 matches in both fixtures, so this run does not establish that
every keyword in the requested viewport was decorated.

Find correctness compared exact UTF-16 locations: 5,900,003 and 10,206,608 for
the 10 MiB middle/near-end markers, and 52,153,803 and 104,578,448 for the
100 MiB markers. Expected and observed locations matched; the absent case
returned no range.

### 6.3 Cancellation observation

| Fixture / operation | Median | p95 | Worst | Cancellation observed in all samples? |
| --- | ---: | ---: | ---: | --- |
| 10 MiB analysis | 0.002 | 0.006 | 0.006 | No; analysis completed first |
| 10 MiB absent find | 0.721 | 4.665 | 4.665 | Yes |
| 100 MiB analysis | 0.002 | 0.004 | 0.004 | No; analysis completed first |
| 100 MiB absent find | 0.660 | 1.225 | 1.225 | Yes |

The analysis numbers are completion-observation intervals after a late cancel
request, not cancellation latency. They fail the “active cancellation observed”
condition. Find cancellation was observed within 250 ms, but the missing
worker-start barrier means a signposted run is still required before accepting
the product cancellation gate.

## 7. Raw latency samples

These are the authoritative raw values used for the tables above.

### BF-01 10 MiB

```text
load: 13.872625, 12.722708, 12.538875, 12.638834, 12.319791, 12.333792, 12.041209, 12.019166, 12.282209, 12.379166
viewport.start: 1.138042, 1.111917, 1.116667, 1.133958, 1.107542, 1.112375, 1.110542, 1.113083, 1.094250, 1.153584
viewport.middle: 1.470167, 1.405166, 1.408666, 1.514750, 1.402667, 1.461084, 1.391375, 1.387417, 1.397667, 1.442458
viewport.end: 0.727667, 0.728875, 0.704667, 0.702792, 0.700250, 0.700459, 0.694291, 0.693334, 0.697042, 0.691791
edit.start: 1.800000, 1.526542, 1.491250, 1.497250, 1.499875, 1.497292, 1.489625, 1.472583, 1.453959, 1.472500
edit.middle: 1.597333, 1.542667, 1.537083, 1.512833, 1.509666, 1.505959, 1.504334, 1.504583, 1.512125, 1.541583
edit.end: 1.143125, 1.115500, 1.113584, 1.118167, 1.105625, 1.112417, 1.121292, 1.105958, 1.103916, 1.101042
visible-analysis: 4.490334, 0.293333, 0.280125, 0.285875, 0.284584, 0.282542, 0.288250, 0.291833, 0.284375, 0.280208
highlight-layout: 4.478000, 4.366750, 4.350875, 4.368167, 4.346291, 4.363416, 4.360375, 4.392416, 4.358041, 4.374125
find.middle: 8.024125, 7.977916, 7.744541, 7.761000, 7.913000, 8.001542, 7.671500, 7.759625, 7.666292, 7.948291
find.near-end: 9.624166, 9.645958, 9.649166, 9.601667, 9.619875, 9.670833, 9.602167, 10.825708, 10.797709, 10.160375
find.absent: 14.734792, 10.075292, 10.043000, 9.886291, 9.912792, 9.797666, 9.683167, 9.852750, 10.041542, 10.047583
cancel.analysis: 0.005750, 0.004375, 0.002500, 0.002042, 0.001834, 0.000708, 0.005375, 0.000416, 0.002167, 0.001625
cancel.find: 0.782292, 0.727542, 0.746958, 0.715291, 0.663250, 0.697000, 0.625417, 0.703500, 0.859166, 4.664875
undo: 0.371875, 0.359083, 0.355583, 0.352041, 0.351875, 0.355417, 0.353709, 0.350792, 0.350042, 0.372834
redo: 0.354292, 0.347833, 0.351458, 0.345875, 0.345291, 0.345291, 0.346083, 0.344292, 0.345375, 0.363708
```

### BF-01 100 MiB

```text
load: 81.289250, 71.663375, 72.081917, 71.807792, 71.352500, 71.328667, 72.306625, 70.035583, 68.495625, 68.404875
viewport.start: 1.118500, 1.102834, 1.107166, 1.093208, 1.076834, 1.083459, 1.081500, 1.083833, 1.075083, 1.119792
viewport.middle: 0.681709, 0.682000, 0.695708, 0.675125, 0.687083, 0.668375, 0.673959, 0.672084, 0.671250, 0.674834
viewport.end: 0.686916, 0.687459, 0.733625, 0.689375, 0.687375, 0.700916, 0.686416, 0.679334, 0.685042, 0.686500
edit.start: 1.647500, 1.497209, 1.487666, 1.461208, 1.462542, 1.438000, 1.445542, 1.447834, 1.444792, 1.438834
edit.middle: 2.101250, 1.895042, 1.884709, 1.878875, 1.882666, 1.896416, 1.875667, 1.887917, 1.895125, 1.869583
edit.end: 1.131666, 1.133250, 1.122834, 1.112041, 1.113417, 1.126292, 1.106500, 1.104250, 1.113042, 1.107584
visible-analysis: 4.355167, 0.289542, 0.280833, 0.285417, 0.285584, 0.290417, 0.292125, 0.290459, 0.288125, 0.294417
highlight-layout: 4.251584, 4.228292, 4.205667, 4.209500, 4.203792, 4.206709, 4.202667, 4.198375, 4.207583, 4.196833
find.middle: 45.466542, 45.406834, 45.337041, 45.484291, 45.608500, 45.723791, 46.050708, 46.024833, 45.540667, 45.819000
find.near-end: 97.204250, 96.918375, 96.930917, 97.567208, 96.292541, 97.822625, 96.235500, 96.399666, 96.381875, 96.060500
find.absent: 88.803292, 89.193333, 88.590875, 88.727750, 89.006333, 89.836708, 90.926833, 90.894625, 90.382625, 91.064750
cancel.analysis: 0.001166, 0.004416, 0.002625, 0.002375, 0.002041, 0.002500, 0.002000, 0.001708, 0.002333, 0.000375
cancel.find: 0.782375, 0.737458, 0.699625, 0.670250, 0.633542, 0.629542, 0.596375, 1.224792, 0.650334, 0.649584
undo: 0.427083, 0.398042, 0.384291, 0.386833, 0.383792, 0.389083, 0.405334, 0.391708, 0.402542, 0.383792
redo: 0.366459, 0.343583, 0.342416, 0.345750, 0.345458, 0.347291, 0.385208, 0.347708, 0.369541, 0.342709
```

## 8. Memory, Instruments and leak evidence

`/usr/bin/time -l` measures the complete process: fixture generation and the
retained fixture string, attributed editor storage, AppKit/framework state,
find buffers and the evidence runner. It is not editor-only incremental RSS.

| Fixture | Maximum RSS | MiB |
| --- | ---: | ---: |
| 10 MiB | 166,903,808 bytes | 159.172 |
| 100 MiB | 588,021,760 bytes | 560.781 |

There is no approved editor-specific RSS ceiling in
`PERFORMANCE_BUDGET.md`. These values therefore establish a baseline only and
cannot be labelled a memory-budget pass.

The 100 MiB Allocations trace launched the exact release binary and ended when
the target exited 0. The saved trace was 127 MiB. The separate Time Profiler
trace also ended with target exit 0 after 5.647 seconds; exported
`potential-hangs` and `hang-risks` tables contained no event rows, and the
thermal state remained nominal. This short headless trace does not establish
interactive paint latency, an eight-hour soak or absence of UI hangs.

`leaks --atExit` exited 1 and reported:

```text
Process: 89,901 nodes malloced for 262,268 KB
Leaks: 287 nodes for 18,720 bytes (18.281 KiB)
Root summary: three NSXPCConnection cycles
```

The root cycles were in AppIntents/LinkServices connections to
`com.apple.linkd.autoShortcut`; no `TextKitEditorSpike`,
`TextKit2EditorHarness`, `NSTextLayoutManager` or `NSTextContentStorage` symbol
appeared in the reported leak roots. This is residual framework evidence, not
“zero leaks,” and it must be rechecked inside the production app/soak.

Transient trace files were not committed because they contain local process
and device metadata. The sanitized commands, exit status and observations
needed after prototype disposal are recorded here.

## 9. Functional, safety and accessibility evidence

Positive evidence from the 20-test native suite includes:

- exact deterministic 10/100 MiB fixture invariants and hashes;
- explicit TextKit 2 component identity with zero ordinary fallback events;
- a debug positive control that detects an intentional TextKit 1 switch;
- start/middle/end edits, exact inserted text and local forced layout;
- native edits invalidating stale analysis revisions;
- input/output/span caps for untrusted analyzer output;
- native oversized insert/delete/document-growth rejection;
- structured analysis/find cancellation tests and Unicode/chunk-boundary find;
- grouped native undo/redo UTF-8/UTF-16 accounting and a 100-level history cap;
- 100 MiB large-file mode disabling folding and semantic completion;
- direct document-selector dispatch, first-responder state, AppKit text-area
  role/label/help/editable metadata and in-memory selection restoration.

The accessibility evidence is metadata and direct-selector smoke only. It does
not establish physical key-equivalent routing through the responder chain,
focus order, a manual VoiceOver read/edit/navigation session, Reduce Motion or
Light/Dark visual behavior. Production warnings are not part of this spike.
The standard-mode policy flags/help describe whether large-file degradation
would allow folding and semantic completion; neither feature is implemented by
the spike, so that text is not feature-availability evidence.

## 10. Acceptance mapping

| DF-M0-003 requirement | Disposition |
| --- | --- |
| BF-01 deterministic 10/100 MiB fixture | Met |
| 10 MiB p95 input-to-paint ≤16.7 ms | **Not established**; hidden forced-layout proxy p95 ≤1.800 ms only |
| 100 MiB p95 input-to-paint ≤50 ms | **Not established**; proxy p95 ≤2.101 ms; large-file degradation did activate |
| First matching find result ≤300 ms | Met on this developer host; worst p95 97.823 ms at 100 MiB |
| Bounded visible analysis/highlighting | Partially met; bounded and validated, but 1,024-span output cap was reached |
| Cancellation worker stops ≤250 ms | Partially met; find observed, analysis completed before cancel, no worker-start/signpost proof |
| Start/middle/end edit and native undo | Met for the spike; bounded history and byte/revision regressions pass |
| Keyboard behavior | Direct selector smoke met; real key events/responder routing not established |
| VoiceOver/accessibility | Metadata smoke met; manual VoiceOver not established |
| Recovery | In-memory selection reconstruction met; durable draft/crash recovery not established |
| RSS/Instruments | Baselines and residual leaks recorded; no editor-specific RSS gate or long soak |
| M1/16 GiB release floor | Not run |
| BF-01 multi-cursor/format/completion cancellation | Out of this bounded spike and not established |
| Prototype disposal | Required after report/ADR commit; disposal commit is recorded by the follow-up update |

The backlog acceptance criterion is therefore not fully passed. Lowering or
reinterpreting it would hide missing user-facing evidence.

## 11. Database safety and security impact

No database connection, SQL execution, write, retry, transaction or result set
exists, so this spike provides no database-operation safety evidence. All SQL
text is deterministic synthetic input. There is no secret model, Keychain,
environment-secret print, connection string, row log, clipboard path or
persisted history. Native edit, affected-range, analysis input/output and find
input/chunk limits reject oversized work inside the synthetic harness. The
document cap relies on generator-supplied fixture metadata; because file I/O is
out of scope, this is not evidence that a production loader validates untrusted
file bytes before decoding/allocation.

The targeted source-commit secret-pattern scan found no credential/private-key
pattern. Dedicated secret-scanner tooling was unavailable, so production CI's
secret scan remains a separate gate.

## 12. Disposition and production re-entry criteria

**Conditionally retain TextKit 2 as the planning candidate behind the focused
AppKit presentation boundary. Defer production implementation approval.**

The spike gives useful positive evidence for explicit TextKit 2 construction,
viewport-bounded work, chunked find, large-file degradation and native
selection/undo invariants. It does not justify copying the prototype into an
application target or claiming the SQL editor is ready.

Before DF-M2-003 can enter implementation review, all of the following are
required:

1. A visible app-host benchmark on the Apple M1/16 GiB floor measuring real
   input event → Core Animation presented frame for start/middle/end edits.
2. An editor-only incremental RSS ceiling approved before measurement, followed
   by 10/100 MiB and repeated-open/close/soak evidence.
3. Real key-equivalent/responder-chain tests and a documented manual VoiceOver
   navigation/editing session, plus Light/Dark and focus-order checks.
4. Durable draft/crash recovery with atomic persistence and corruption/failure
   tests; selection reconstruction alone is insufficient.
5. Worker-start/signpost cancellation evidence for analysis and find, including
   stale-result suppression in the visible host.
6. A separate parser/highlighting/completion dependency and security/license
   decision; safety-critical SQL classification remains outside the editor.

The complete `spikes/textkit-editor` directory is disposable and must be
deleted after this report and ADR are committed. Future production code must be
implemented under `QueryEditor`/`SharedUI` boundaries from the reviewed
contract, not promoted wholesale from the spike.

## 13. Primary platform references

- [Apple `NSTextView` documentation](https://developer.apple.com/documentation/appkit/nstextview)
- [Apple TextKit 1-switch notification](https://developer.apple.com/documentation/appkit/nstextview/didswitchtonslayoutmanagernotification)
- [WWDC21: Meet TextKit 2](https://developer.apple.com/videos/play/wwdc2021/10061/)
- [Apple accessibility for AppKit](https://developer.apple.com/documentation/appkit/accessibility-for-appkit)
