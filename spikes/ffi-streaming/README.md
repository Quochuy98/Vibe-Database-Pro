# DF-M0-001 — bounded C ABI streaming spike

Status: disposable feasibility spike; Rust/Swift evidence run complete on the
developer machine; not production code

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
- Rust unit tests plus SwiftPM integration tests, including a one-million-row
  checksum run.

Excluded:

- real databases, drivers, network sockets, credentials and Keychain;
- callbacks, re-entrant UI delivery, MainActor proof and XPC;
- production module placement, public API stability, signing/notarization and
  a full Xcode application target;
- proof that a real allocator OOM or an invalid native pointer is catchable.

## Contract summary

The canonical header is [`include/dataforge_ffi_spike.h`](include/dataforge_ffi_spike.h).
SwiftPM and the C compiler compile that header; the Rust crate mirrors the
fixed-width `repr(C)` records and asserts their sizes at compile time (the
spike deliberately avoids a binding-generator dependency). All v1 records
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
- No secret is accepted, generated, logged or persisted. Fault tests use no
  secret-like payload.
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

From this directory, with Rust 1.97.1 installed by the official `rustup`
toolchain and an arm64 macOS host:

```sh
export MACOSX_DEPLOYMENT_TARGET=14.0
cargo fmt --manifest-path rust/Cargo.toml -- --check
clang -std=c11 -Wall -Wextra -Werror -I include -fsyntax-only include/shim.c
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml --all-targets -- --test-threads=1
cargo build --manifest-path rust/Cargo.toml --release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcrun swift test -c release --scratch-path .build-xcode
```

The convenience runner is `scripts/test.sh`; it builds Rust before Swift and
captures `/usr/bin/time -l` output under ignored `artifacts/`. The test target
uses XCTest, so the runner selects the installed full Xcode toolchain. A bare
Command Line Tools `swift test` on this host cannot import XCTest; that exact
failure is recorded as an environment limitation rather than hidden. If the
toolchain is compared, use a separate scratch path and never mix its SwiftPM
cache with another Swift version. Xcode can generate a temporary SwiftPM
scheme, and that package build/test was run; this is not an Xcode production
app target or UI-runtime validation.

## Evidence record

The following entries are from the completed evidence run; they do not claim
production capability.

| Evidence | Result |
| --- | --- |
| Rust toolchain / target | Rust 1.97.1 (`aarch64-apple-darwin`), `MACOSX_DEPLOYMENT_TARGET=14.0` |
| Swift toolchain / target | Passing run: Xcode 26.0.1 / Swift 6.2, arm64e macOS 14 deployment; CLT Swift 6.3.3 could compile the library but its `swift test` lacked XCTest |
| Host | `arm64`, macOS 26.5.2, 24 GiB developer machine; not the proposed M1/16 GiB release floor |
| Format / clippy / Rust tests | Pass: `cargo fmt --check`; `cargo clippy --all-targets -- -D warnings`; 8 Rust tests passed |
| Swift release integration | Pass: 7 XCTest cases, 0 failures, via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test -c release` |
| One-million-row checksum | `rows=1,000,000`, `chunks=1,000`, digest `16282154771318798373` |
| RSS | Final runtime bundle measurement: 61,915,136 bytes maximum RSS (~59 MiB) under `/usr/bin/time -l xcrun xctest` (observed ~61.8–62.0 MB across runs); process-level developer evidence, not incremental app RSS |
| Static ABI link | Swift release test linked the Rust `staticlib` and exercised all exported symbols successfully |
| Xcode package validation | Pass: `xcodebuild ... build -quiet` and `xcodebuild ... test -quiet` with arm64 destination (generated SwiftPM scheme; no production app target) |
| Panic output | Expected Rust panic-hook lines appear for fault probes; returned status is controlled and no secret-like data is emitted |
| Sanitizers / Miri / lint tools | ASan/TSan/Miri not run: this pinned stable toolchain lacks a configured sanitizer/Miri harness. `cargo-audit`, `cargo-deny`, `swiftformat` and `swiftlint` are unavailable on this host. Residual risk: wild-pointer/low-level race behavior and supply-chain lint need dedicated CI jobs |

## Disposal and decision

This directory is a throwaway artifact for M0. After review, retain only the
measured report/contract decision in [`docs/adr/0008-m0-ffi-spike-disposition.md`](../../docs/adr/0008-m0-ffi-spike-disposition.md)
(and supersede ADR-0003 if a later recommendation changes), then delete `spikes/ffi-streaming` before production
modules are created. No file here may be imported by an application target or
presented as a shipped feature.
