# ADR-0008: M0 C ABI streaming spike disposition

Status: Accepted for planning; disposable prototype removed; production
implementation remains gated

Date: 2026-07-30

Supersedes: No prior decision is rewritten. This record refines the evidence
required by [ADR-0003](0003-swift-rust-bridge.md).

## Context

ADR-0003 selected a narrow versioned C ABI but left the exact chunk ownership,
backpressure and cancellation mechanics to an M0 spike. The spike had to prove
that a Swift consumer can receive typed data without transferring Rust layout,
retaining a caller pointer, growing an unbounded queue or allowing a panic to
cross C. The planning performance budget sets a hard per-chunk maximum of 1,000
rows and 4 MiB encoded bytes.

## Evidence

The durable command, result, failure and measurement record is
[`docs/reports/DF-M0-001-ffi-streaming-evidence.md`](../reports/DF-M0-001-ffi-streaming-evidence.md).
The disposable artifact is retained only in evidence source commit
`ce33ff1bf8b81a7bc7a5c78e56d57e58f25f70a2`. On an arm64 Mac15,3 developer
machine (macOS 26.5.2, 24 GiB), with Rust 1.97.1, nightly 1.99.0 and Xcode
26.0.1/Swift 6.2:

- Rust format, clippy with `-D warnings`, 13 native tests, the complete 13-test
  ASan/TSan matrices and seven targeted Miri tests passed. The expanded suite
  includes independent reference-model property cases and same-handle
  cancel/next/release races.
- Swift release integration passed 8 XCTest cases, including ABI/layout,
  advertised-short fields inside fully allocated records, row/byte caps,
  pull/ack, cancellation, panic/allocation faults, secret-like destination
  canary, typed row parsing and registry cleanup. It did not allocate a record
  shorter than its inflated `struct_size`; the production contract below closes
  that post-run review gap.
- `xcodebuild` generated SwiftPM scheme build and arm64 test passed.
- The one-million-row run produced 1,000 chunks and deterministic digest
  `16282154771318798373`.
- The latest post-build `xcrun xctest` run measured 61,915,136 bytes maximum
  RSS. Separate benchmark processes measured 5,832,704 bytes idle and
  10,780,672 bytes full maximum RSS (approximate delta 4,947,968 bytes).
- One warm-up plus ten one-million-row samples measured 106.683 ms median and
  154.003 ms p95/worst. The explicit two-copy model moved 76,800,000 bytes per
  sample and retained no Rust chunk bytes after `next`.

The fake canary was absent from every captured artifact. Swift ASan stalled in
runtime shadow-memory initialization and Swift TSan exited with signal 11
before XCTest; exact attempts and diagnostics remain in the durable report.
No database, driver, network, credential, production module or customer data
was used.

## Decision

For the next production design review, retain the following planning contract:

1. Use versioned fixed-width records beginning with `struct_size` and
   `abi_version`, and pass the readable allocation length independently of the
   embedded `struct_size`. Treat neither a non-null pointer nor caller-supplied
   `struct_size` as proof that tail memory is readable. Before reading or
   copying, validate pointer/length pairing, minimum and maximum readable
   lengths, supported minimum and maximum record sizes, and every offset/length
   calculation with checked arithmetic. A future alternative may use one fixed
   record per ABI version with no advertised tail, but it requires equivalent
   mismatch tests.
2. Use opaque `uint64_t` handles with slot generations and a bounded registry
   (128 streams in the spike hypothesis); stale generations cannot access a
   reused slot.
3. Let Swift provide the destination byte buffer. Rust validates capacity,
   copies only during `next`, and retains no pointer after return. This removes
   the Rust-owned-buffer use-after-release class. Treat the return status and
   outputs as one tagged result, with no partial success:
   - `OK` copies exactly `byte_count` bytes for `row_count` rows, returns a
     positive sequence and requires its matching ACK only after Swift validates
     metadata size/version, bounds, encoding and checksum;
   - `TERMINAL` is end-of-stream with no chunk and no ACK;
   - `BUFFER_TOO_SMALL` copies nothing, advances no cursor, creates no
     outstanding demand and returns only a bounded `required_capacity` for a
     bounded retry;
   - `CANCELLED` has no chunk and no ACK; `NEEDS_ACK` creates no new chunk and
     leaves the previous sequence outstanding; and
   - every other non-`OK` status is a typed error with no consumable chunk and
     no ACK. All fallible validation and state preparation must finish before
     the copy so an error cannot expose bytes that the caller cannot safely
     consume or acknowledge. If Swift rejects an `OK` payload during validation
     or decoding, it uses an explicit abort/cancel path and never sends a
     success ACK merely to release the stream.
4. Allow one outstanding logical chunk per stream. A second pull returns
   `NEEDS_ACK`; only the matching sequence ACK advances the cursor. Hard caps
   are 1,000 rows and 4 MiB encoded bytes, whichever is reached first.
5. Model cancellation as a state transition. A chunk already linearized before
   cancellation must still be acknowledged; terminal state is not claimed
   until the state machine has evidence.
6. Wrap every exported entry in panic containment and map simulated allocation
   failure to a typed status. Real allocator OOM, SIGSEGV and wild non-null C
   pointers remain outside `catch_unwind` guarantees.

This is a contract recommendation, not an accepted production API. A future
implementation must add a Swift facade/`AsyncSequence`, supervised Rust
runtime, driver cancellation mapping, working Swift integration sanitizer
evidence and a new review before importing any spike code.

## Consequences and residual risk

Caller-owned buffers simplify lifetime safety but require the production facade
to serialize `next`/ACK and preserve explicit sequence state. The spike uses a
single registry mutex and a fake synchronous producer; it does not prove
database-driver cancellation, callback executor behavior, MainActor isolation,
server interruption truth or release/distribution packaging. Rust ASan/TSan and
targeted Miri now cover the spike, but Swift sanitizer integration still needs a
working CI host/toolchain before production release. Those remaining concerns
stay M0 unknowns and release blockers where listed in `docs/RISKS.md`.

No database write, retry, transaction or credential path exists in this spike,
so it cannot be used as evidence that database safety requirements are met.

## Disposal

The remediation disposition checked every initial independent-review blocker
against the durable report, then removed `spikes/ffi-streaming`. This ADR and
the report remain; the recorded evidence commit keeps the exact disposable
source auditable through Git history. Recreate production code under the
approved module boundaries rather than copying the spike wholesale. If a future
implementation chooses Rust-owned leases, callbacks, a different cap or
UniFFI, create a superseding ADR with equivalent ownership, cancellation,
memory and security evidence.
