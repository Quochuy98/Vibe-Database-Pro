# ADR-0008: M0 C ABI streaming spike disposition

Status: Evidence recorded; production implementation remains gated

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

The disposable artifact is [`spikes/ffi-streaming`](../../spikes/ffi-streaming/README.md).
On an arm64 Mac15,3 developer machine (macOS 26.5.2, 24 GiB), with Rust
1.97.1 and Xcode 26.0.1/Swift 6.2:

- Rust format, clippy with `-D warnings`, 8 unit tests and the one-million-row
  fake stream passed.
- Swift release integration passed 7 XCTest cases, including ABI/layout,
  malformed input, row/byte caps, pull/ack, cancellation, panic/allocation
  faults, typed row parsing and registry cleanup.
- `xcodebuild` generated SwiftPM scheme build and arm64 test passed.
- The one-million-row run produced 1,000 chunks and deterministic digest
  `16282154771318798373`.
- The latest post-build `xcrun xctest` run measured 62,128,128 bytes maximum
  RSS (observed runs were approximately 61.8–62.2 MB). This
  is process-level developer evidence, not a claim about incremental app RSS
  or the proposed M1/16 GiB release floor.

Exact commands and skips are recorded in the spike README. No database,
driver, network, credential, production module or customer data was used.

## Decision

For the next production design review, retain the following planning contract:

1. Use fixed-width records beginning with `struct_size` and `abi_version`;
   reject short/incompatible records before copying the advertised tail.
2. Use opaque `uint64_t` handles with slot generations and a bounded registry
   (128 streams in the spike hypothesis); stale generations cannot access a
   reused slot.
3. Let Swift provide the destination byte buffer. Rust validates capacity,
   copies only during `next`, and retains no pointer after return. This removes
   the Rust-owned-buffer use-after-release class.
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
runtime, driver cancellation mapping, thread sanitizer evidence and a new
review before importing any spike code.

## Consequences and residual risk

Caller-owned buffers simplify lifetime safety but require the production facade
to serialize `next`/ACK and preserve explicit sequence state. The spike uses a
single registry mutex and a fake synchronous producer; it does not prove
database-driver cancellation, callback executor behavior, MainActor isolation,
server interruption truth, sanitizer coverage or release/distribution
packaging. Those remain M0 unknowns and release blockers where listed in
`docs/RISKS.md`.

No database write, retry, transaction or credential path exists in this spike,
so it cannot be used as evidence that database safety requirements are met.

## Disposal

After review, delete `spikes/ffi-streaming` and retain this ADR plus the
measured report facts. Recreate production code under the approved module
boundaries rather than copying the spike wholesale. If a future implementation
chooses Rust-owned leases, callbacks, a different cap or UniFFI, create a
superseding ADR with equivalent ownership, cancellation, memory and security
evidence.
