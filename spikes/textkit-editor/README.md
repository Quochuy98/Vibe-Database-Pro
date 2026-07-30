# DF-M0-003 — disposable TextKit 2 editor feasibility spike

This directory is a deliberately disposable technical spike. It is not a
production editor, is not linked to a database, and must not be imported by a
future application target.

## Hypothesis

An `NSTextView` backed explicitly by TextKit 2 can keep synthetic BF-01 SQL
editing usable at 10 MiB, enter an explicit reduced-feature mode at 100 MiB,
decorate only a bounded visible-range snapshot, find incrementally off the
`MainActor`, retain native keyboard/undo/accessibility behavior, and cooperate
with structured cancellation.

The provisional budgets being tested are:

- 10 MiB edit-to-paint p95 at or below 16.7 ms, routine worst at or below 50 ms;
- 100 MiB stress edit-to-paint p95 at or below 50 ms with expensive features
  explicitly disabled;
- first find result in the 100 MiB fixture at or below 300 ms;
- analysis cancellation observed within the product's 250 ms worker target;
- no whole-document highlighting or parsing on the `MainActor`.

The executable's forced-layout timing is a repeatable proxy, not a complete
input-to-screen measurement. Its cancellation number requests cancellation
1 ms after task creation, without a worker-start barrier, and measures
structured-child termination; the analyzer checks cancellation before work and
every bounded stride. Instruments
signposts are still required to prove the exact running checkpoint. Instruments
Hangs, Time Profiler, Allocations, Leaks, Accessibility Inspector, VoiceOver,
and a visible app-host run are still required before accepting the editor
decision.

## Bounded scope

The package contains only:

- a deterministic, in-memory BF-01 generator for exact 10 MiB and 100 MiB
  fixtures with 100,000 mixed PostgreSQL/MySQL-like statements, Unicode, long
  comments, dollar bodies, and intentional syntax errors;
- a hidden AppKit host with an explicit `NSTextContentStorage` →
  `NSTextLayoutManager` → `NSTextContainer` → `NSTextView` network and a
  pre-construction observer that treats any TextKit 1 fallback as a failure;
- start/middle/end edits, TextKit 2 rendering attributes, undo/redo, native
  command selectors, accessibility metadata, and selection recovery;
- a viewport analyzer capped at 65,536 UTF-16 units and 1,024 matches;
- an incremental find actor capped at 115 Mi UTF-16 units, searching in 4 Mi
  UTF-16-unit chunks with cooperative cancellation and middle, near-end, and
  absent-marker correctness cases;
- XCTest functional/cancellation coverage and a release evidence executable.

The 100 MiB mode disables folding and semantic completion while preserving
plain editing, bounded visible highlighting, find, undo, keyboard commands,
selection recovery, and accessibility metadata. Individual edits are capped at
4 KiB and documents at 110 MiB in this spike. Analyzer configuration cannot
exceed 65,536 UTF-16 units or 1,024 matches; find configuration cannot exceed
115 Mi UTF-16 document units, a 1,024-unit needle, or a 16 Mi-unit chunk.

Out of scope: query execution, database connectivity, credentials, persistence,
history, completion, a real SQL parser, formatting, folding implementation,
multiple cursors, file I/O, crash recovery storage, signing/distribution, and
production architecture. Fixture strings and diagnostics contain no customer
data or secrets; output includes only sizes, a deterministic SHA-256 fixture
fingerprint, timings, feature state, and machine characteristics.

## Run

Full Xcode is required because the active Command Line Tools selection alone
cannot run `xcodebuild` in this workspace. The script keeps all SwiftPM build
artifacts in a temporary directory and removes them on exit.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./scripts/test.sh
```

The script runs strict `swift-format` lint, debug build, XCTest, release build,
then one warm-up plus ten release samples per edit position and find scenario
for each fixture. JSON includes every raw sample plus median, nearest-rank p95,
and worst. `/usr/bin/time -l` reports process maximum resident set size
separately for 10 MiB and 100 MiB. Set `TEXTKIT_SPIKE_SAMPLES` to a value of at
least 10 for additional samples. That process maximum includes fixture
generation storage, the retained fixture string, attributed editor storage,
AppKit/framework state, and bounded find buffers; it is not an editor-only
incremental RSS number.

The JSON budget booleans are evidence, not assertions in the functional suite:
timing variance must not be hidden by weakening tests or increasing a timeout.
Record OS build, hardware, Xcode/Swift, sample count, median, p95, worst, maximum
RSS, and Instruments observations when disposing the spike.

## Success and disposition

The spike succeeds only if the 10 MiB budget passes on the named M1 16 GB
baseline; the 100 MiB stress result is measured with graceful large-file mode;
undo/redo, start/middle/end editing, first find, keyboard selectors, selection
recovery, accessibility/VoiceOver, bounded visible highlighting, cancellation,
RSS, hangs, and leaks have exact evidence. A headless XCTest pass alone is not
enough to claim accessibility or paint performance.

The JSON names these checks as smoke/proxy evidence and records the corresponding
unestablished runtime claims as `false`. The harness only verifies selector
dispatch, a window first-responder, AppKit accessibility properties, and
in-memory selection reconstruction. It does not
prove key-equivalent event routing, manual VoiceOver behavior, actual
input-to-frame paint, durable crash recovery, Instruments hangs/leaks, or
Light/Dark appearance. There is currently no approved editor-specific RSS
ceiling, so maximum RSS is recorded without declaring a memory-budget pass.
Measurements on a developer machine other than the named M1/16 GB baseline are
diagnostic and cannot close the release gate.

After recording the measured evidence and an adopt/reject/defer decision in a
separately reviewed durable report/ADR, delete this entire directory. Rebuild
the chosen design in reviewed production modules; do not promote or copy the
prototype wholesale.
