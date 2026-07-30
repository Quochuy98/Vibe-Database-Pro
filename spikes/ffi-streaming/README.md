# DF-M0-001 — bounded C ABI streaming spike

Status: disposable feasibility spike; remediation evidence complete on the
developer machine; independent re-review required before disposal; not
production code

## Hypothesis

A narrow, versioned C ABI can let a Swift consumer pull deterministic typed
chunks from a Rust producer without transferring Rust layouts, retaining a
borrowed pointer, growing an unbounded queue, or allowing a panic to cross the
boundary. The spike deliberately uses a fake producer only. It does not prove a
database driver, network protocol, UI runtime, or production FFI API.

## Scope and non-goals

Included:

- fixed-width C records with an ABI/feature handshake;
- opaque `uint64_t` handles encoded with a slot and generation;
- a bounded registry of 128 streams;
- pull/ack flow with exactly one outstanding logical chunk;
- caller-owned destination buffers (Rust borrows the pointer only during
  `next` and retains no pointer after return);
- hard per-chunk limits of **1,000 rows and 4 MiB encoded bytes**, whichever
  comes first;
- deterministic little-endian typed-row encoding;
- cancellation states, terminal status, idempotent release and stale-handle
  rejection;
- panic containment at every exported entry point and simulated allocation
  failure;
- deterministic reference-model/property tests, same-handle race tests, Miri,
  Rust ASan/TSan and SwiftPM integration tests, including a one-million-row
  checksum run;
- a release benchmark with one warm-up, ten measured samples, explicit copy
  accounting and separate idle/full process RSS measurements.

Excluded:

- real databases, drivers, network sockets, credentials and Keychain;
- callbacks, re-entrant UI delivery, MainActor proof and XPC;
- production module placement, public API stability, signing/notarization and
  a full Xcode application target;
- proof that a real allocator OOM or an invalid native pointer is catchable.

## Contract summary

The canonical header is [`include/dataforge_ffi_spike.h`](include/dataforge_ffi_spike.h).
SwiftPM and the C compiler compile that header; the Rust crate mirrors the
fixed-width `repr(C)` records and asserts size, alignment and every field offset
at compile time (the spike deliberately avoids a binding-generator dependency).
All v1 records
begin with `struct_size` and `abi_version`. Known fields are fixed-width
integers; larger future tails are ignored, while a short record or non-zero
reserved field is rejected.

| Function | Ownership and lifecycle | Success/state effect |
| --- | --- | --- |
| `df_spike_abi_negotiate_v1` | Caller owns request/response records; output is written synchronously | Returns supported features and hard limits |
| `df_spike_stream_create_v1` | Caller owns options and output handle; registry owns stream state | Creates one `READY` stream or returns a bounded error |
| `df_spike_stream_next_v1` | Caller owns writable `destination`; Rust retains no pointer after return. `out_meta` is written synchronously | Copies one bounded chunk and enters `OUTSTANDING`; undersized buffers do not advance state |
| `df_spike_stream_ack_v1` | Sequence is a value, not a pointer | Matching ACK advances the cursor; final ACK enters `COMPLETED` |
| `df_spike_stream_cancel_v1` | Caller owns outcome record | `READY` cancels immediately; outstanding chunk becomes `CANCEL_PENDING_ACK` until matching ACK |
| `df_spike_stream_get_status_v1` | Caller owns snapshot record; snapshot may be stale immediately | Reports state, cursor and terminal/error category |
| `df_spike_stream_release_v1` | Removes registry state only when no chunk is outstanding; repeated release of the last generation is idempotent | Frees a slot; stale generations cannot affect a reused slot |

Every exported function is wrapped in `catch_unwind`. A panic returns
`PANIC`; it never unwinds through C. The registry mutex explicitly recovers from
poisoning. `release` returns `NEEDS_ACK` while a logical chunk is outstanding,
so cleanup cannot silently skip the caller's acknowledgement obligation.

## State and thread contract

```text
READY --next--> OUTSTANDING --ack--> READY/COMPLETED
  |                 |
 cancel          cancel
  |                 |
CANCELLED   CANCEL_PENDING_ACK --ack--> CANCELLED
```

All calls are synchronous and linearizable under one bounded registry mutex;
there are no callbacks or unmanaged tasks. A second `next` before ACK returns
`NEEDS_ACK`. `cancel` may be called by another thread, but it linearizes before
or after the current call; no post-cancel chunk is published. The production
facade should serialize normal `next`/`ack`/`status`/`release` calls and map
Swift task cancellation to the cancel function.

## Deterministic row encoding

Each row starts with 24 bytes in little-endian order:

| Offset | Width | Value |
| ---: | ---: | --- |
| 0 | 8 | row index (`u64`) |
| 8 | 8 | `i64` value (`index XOR seed`) |
| 16 | 4 | text length (`0` for NULL, otherwise `16`) |
| 20 | 1 | boolean (`index` odd) |
| 21 | 1 | NULL marker (`index % 10 == 0`) |
| 22 | 2 | reserved zero |
| 24 | 0 or 16 | lowercase hexadecimal index text |

The chunk metadata includes an FNV-1a checksum over the copied bytes. The Swift
test independently parses every row, checks ordering/type/null semantics and
checks the one-million-row aggregate digest.

## Safety and security notes

- No database operation or write path exists; database safety impact is limited
  to proving bounded streaming and cancellation semantics.
- No credential is accepted, generated, logged or persisted. Fault tests place
  a fake secret-like canary in caller-owned destination memory, assert that
  controlled failures do not read or mutate it, and fail if captured artifacts
  contain it.
- Checked arithmetic and `try_reserve_exact` reject malformed/oversized input
  before allocation. The destination capacity is validated before copying.
- The caller-owned buffer removes the Rust-owned pointer/use-after-release
  class. C cannot detect a wild non-null pointer or a caller violating its
  writable/alignment contract; ASan is the appropriate external check.
- `catch_unwind` cannot contain SIGSEGV or a process-aborting real OOM. The
  allocation test is deterministic fault injection, not an OOM claim.
- The registry and temporary chunk allocation are bounded. `in_flight_bytes`
  remains zero because no Rust allocation survives the `next` call.

## Reproducible commands

From this directory, with Rust 1.97.1 plus the 2026-07-30 nightly Miri/rust-src
components installed by the official `rustup` toolchain and an arm64 macOS
host, run the evidence runner:

```sh
rustup toolchain install nightly --profile minimal --component miri
./scripts/test.sh
```

The runner records every exact command in its source and captures output under
ignored `artifacts/`. It covers C/C++ header compilation, Rust fmt/clippy/native
tests, targeted Miri, full Rust ASan/TSan, Swift release integration,
`xcodebuild` package build/test, runtime RSS, benchmark latency/copy accounting
and a canary scan. The test target uses XCTest, so the runner selects full
Xcode. The permanent evidence report preserves commands, results and failures
outside this disposable directory.

## Evidence record

The following entries are from the completed evidence run; they do not claim
production capability.

| Evidence | Result |
| --- | --- |
| Rust toolchain / target | Rust 1.97.1 (`aarch64-apple-darwin`), `MACOSX_DEPLOYMENT_TARGET=14.0` |
| Swift toolchain / target | Passing run: Xcode 26.0.1 / Swift 6.2, arm64e macOS 14 deployment; CLT Swift 6.3.3 could compile the library but its `swift test` lacked XCTest |
| Host | `arm64`, macOS 26.5.2, 24 GiB developer machine; not the proposed M1/16 GiB release floor |
| Format / clippy / Rust tests | Pass: `cargo fmt --check`; `cargo clippy --all-targets -- -D warnings`; 13 Rust tests passed |
| Rust dynamic checks | Pass: 13/13 under nightly ASan, 13/13 under nightly TSan, and 7 targeted ownership/race tests under Miri |
| Swift release integration | Pass: 8 XCTest cases, 0 failures, via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test -c release` |
| One-million-row checksum | `rows=1,000,000`, `chunks=1,000`, digest `16282154771318798373` |
| RSS | XCTest maximum RSS `61,915,136` bytes; benchmark idle/full maximum RSS `5,832,704`/`10,780,672` bytes, an approximate `4,947,968`-byte process delta. These are developer-process measurements, not app incremental RSS |
| Release latency | One warm-up + 10 samples: one-million-row median `106.683 ms`, p95/worst `154.003 ms`; chunk median `0.102417 ms`, p95 `0.146459 ms`, worst `7.343792 ms` |
| Copy model | Per sample: 38,400,000 payload bytes; 1,000 Rust-to-caller copies plus 1,000 Swift wrapper copies; two full-payload copy passes / 76,800,000 copied bytes; no retained Rust chunk bytes |
| Static ABI link | Swift release test linked the Rust `staticlib` and exercised all exported symbols successfully |
| Xcode package validation | Pass: `xcodebuild ... build -quiet` and `xcodebuild ... test -quiet` with arm64 destination (generated SwiftPM scheme; no production app target) |
| Panic output | Expected Rust panic-hook lines appear for fault probes; returned status is controlled and no secret-like data is emitted |
| Swift sanitizers / lint tools | SwiftPM ASan stalled before XCTest in the Xcode ASan runtime; SwiftPM TSan exited with signal 11 before XCTest. Rust ASan/TSan and Miri passed. `cargo-audit`, `cargo-deny`, external `swiftformat` and `swiftlint` remain unavailable; exact failures/skips are in the permanent report |

## Disposal and decision

This directory is a throwaway artifact for M0. After review, retain only the
measured report/contract decision in [`docs/adr/0008-m0-ffi-spike-disposition.md`](../../docs/adr/0008-m0-ffi-spike-disposition.md)
(and supersede ADR-0003 if a later recommendation changes), then delete `spikes/ffi-streaming` before production
modules are created. No file here may be imported by an application target or
presented as a shipped feature.
