# DF-M0-001 — C ABI streaming spike evidence

Status: Remediation evidence recorded; independent disposal re-review pending

Evidence date: 2026-07-30

Evidence source commit: `ce33ff1bf8b81a7bc7a5c78e56d57e58f25f70a2`

## 1. Scope and decision question

This report is the durable evidence required before deleting the disposable
`spikes/ffi-streaming` artifact. It asks only whether a fake Rust producer and
Swift consumer support a viable planning contract for versioned fixed-width C
records, caller-owned bounded chunks, pull/ACK backpressure, cancellation,
opaque-handle lifecycle and panic containment.

It does not establish a production FFI API, database-driver behavior,
MainActor delivery, callback/executor behavior, credentials, UI runtime,
signing or distribution readiness.

An initial independent review rejected disposal because the prior evidence
depended on the directory that would be deleted and lacked property/race,
secret-canary, sanitizer and copy/latency evidence. Commit `ce33ff1` closes
those gaps without changing the recommended ownership model. This report now
survives disposal and makes the remaining limitations explicit.

## 2. Evidence identity and environment

| Item | Recorded value |
| --- | --- |
| Source commit | `ce33ff1bf8b81a7bc7a5c78e56d57e58f25f70a2` |
| Host | Mac15,3, arm64, 24 GiB RAM |
| OS | macOS 26.5.2, build 25F84 |
| Stable Rust | 1.97.1, `aarch64-apple-darwin` |
| Sanitizer/Miri Rust | 1.99.0-nightly (`1a833e165`, 2026-07-29) |
| Xcode / Swift | Xcode 26.0.1 (17A400), Swift 6.2 |
| Deployment target | macOS 14.0 |
| Rust source SHA-256 | `8809a119204d96d28057fd3b9667e1e087bc3e922c55b8dc66798aa69999dbf3` |
| C header SHA-256 | `3206e72e9762bfe5cdde97be7efd0522004835c2492425a565d27dc54c6136ee` |
| Benchmark SHA-256 | `2ba6d756b524ea8d548cb74cd6caa1b44e16c6bc5833cb54eb23a9822ab67be0` |
| Evidence runner SHA-256 | `cdc55d373326722fa40664416c3944f2603b98272ef74f58d1ffdaca582f4a0d` |

The host is not the proposed M1/16 GiB release-floor machine. All measurements
are developer evidence and must not be presented as app or release guarantees.

## 3. Exact commands

The final run used the following commands from `spikes/ffi-streaming`. The
checked-in runner at the evidence commit is the authoritative command order.
Build output and raw timing files were intentionally ignored because they are
generated artifacts; the results needed after disposal are recorded below.

```sh
rustup toolchain install nightly --profile minimal --component miri

export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export DATAFORGE_SECRET_CANARY='<fake runtime canary; value not logged>'

cargo fmt --manifest-path rust/Cargo.toml -- --check
clang -std=c11 -Wall -Wextra -Werror -I include \
  -fsyntax-only include/shim.c
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml --all-targets -- \
  --test-threads=1

for test_name in \
  cancel_and_release_attempts_wait_while_next_holds_registry_lock \
  same_handle_next_cancel_release_races_are_linearizable \
  secret_like_destination_canary_survives_controlled_faults_without_logging \
  malformed_inputs_are_zeroed_and_never_advance_state \
  panic_and_allocation_failures_are_contained \
  stale_handles_cannot_cross_slot_reuse \
  pull_ack_enforces_byte_and_row_caps
do
  cargo +nightly miri test --quiet --manifest-path rust/Cargo.toml \
    "$test_name" -- --test-threads=1
done

RUSTFLAGS='-Zsanitizer=address' \
RUSTDOCFLAGS='-Zsanitizer=address' \
CARGO_TARGET_DIR="$PWD/.build-rust-asan" \
  cargo +nightly test -Zbuild-std --target aarch64-apple-darwin \
  --manifest-path rust/Cargo.toml --all-targets -- --test-threads=1

RUSTFLAGS='-Zsanitizer=thread' \
RUSTDOCFLAGS='-Zsanitizer=thread' \
CARGO_TARGET_DIR="$PWD/.build-rust-tsan" \
  cargo +nightly test -Zbuild-std --target aarch64-apple-darwin \
  --manifest-path rust/Cargo.toml --all-targets -- --test-threads=1

cargo build --manifest-path rust/Cargo.toml --release
xcrun swift test -c release --scratch-path .build-xcode

xcodebuild -scheme DataForgeFFISpike-Package \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build-xcodebuild -quiet build
xcodebuild -scheme DataForgeFFISpike-Package \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build-xcodebuild -quiet test

xcrun swift build -c release --product DataForgeFFIBenchmark \
  --scratch-path .build-xcode
/usr/bin/time -l xcrun xctest \
  .build-xcode/arm64-apple-macosx/release/DataForgeFFISpikePackageTests.xctest
/usr/bin/time -l \
  .build-xcode/arm64-apple-macosx/release/DataForgeFFIBenchmark --idle
/usr/bin/time -l \
  .build-xcode/arm64-apple-macosx/release/DataForgeFFIBenchmark

grep -R -F -q "$DATAFORGE_SECRET_CANARY" artifacts
# Expected grep result: no match; the runner treats a match as failure.
```

The final convenience invocation was:

```sh
./scripts/test.sh
```

It completed with exit status 0.

## 4. Correctness, lifecycle and security results

| Evidence | Result |
| --- | --- |
| C ABI | C11 and C++17 header compilation passed; C, Rust and Swift agree on every record size/alignment and selected/all field offsets |
| Rust native suite | 13 passed, 0 failed; debug and release runs passed |
| Swift integration | 8 XCTest cases passed, 0 failed in release configuration |
| Typed million-row run | 1,000,000 rows, 1,000 chunks, deterministic typed digest `16282154771318798373` |
| Chunk/property model | 96 deterministic random boundary cases plus 256 independent reference-state cases passed |
| Backpressure | A second pull before matching ACK returns `NEEDS_ACK`; undersized destinations do not advance state |
| Cancellation | Ready, outstanding, cancelled, completed and failed boundaries passed; cancel/next/release same-handle race repeated 64 times |
| During-chunk race | A test-only condition-variable hook proved cancel and release reached their lock attempts while `next` held the registry lock; next linearized first, cancel became pending-ACK and release returned `NEEDS_ACK` |
| Handle safety | Never-issued, stale generation, slot reuse, duplicate release, invalid and outstanding-release cases returned controlled statuses |
| Faults | Simulated allocation failure and panic returned typed statuses; panic did not unwind through C |
| Leak invariant | Every Rust case asserted `live_streams == 0`, `in_flight_bytes == 0`, and `created_streams == released_streams`; Swift teardown asserted the same |
| Secret-like canary | Fake canary bytes in caller destinations were unchanged across undersized/allocation/panic failures; captured-artifact scan had zero matches |
| Miri | 7 targeted pointer/ownership/race tests passed |
| Rust AddressSanitizer | Full 13/13 suite passed, including property, race and million-row cases |
| Rust ThreadSanitizer | Full 13/13 suite passed, including same-handle concurrency cases |
| Xcode package | `DataForgeFFISpike-Package` build and test actions passed for arm64 macOS |

The same-handle race is linearizable because the spike serializes registry
operations with one mutex. This is evidence for contract feasibility, not a
recommendation to use a global mutex for production driver work.

## 5. Copy, latency and memory evidence

The benchmark performs one unmeasured warm-up followed by ten measured
one-million-row samples. Percentiles use nearest-rank selection; with ten
samples p95 equals the worst sample.

| Metric | Result |
| --- | ---: |
| Rows / chunks per sample | 1,000,000 / 1,000 |
| Encoded payload per sample | 38,400,000 bytes |
| End-to-end median | 106.683 ms |
| End-to-end p95 / worst | 154.003 ms / 154.003 ms |
| Chunk median | 0.102417 ms |
| Chunk p95 / worst | 0.146459 ms / 7.343792 ms |
| Median throughput | 9,373,539 generated rows/s |
| Benchmark idle maximum RSS | 5,832,704 bytes |
| Benchmark full maximum RSS | 10,780,672 bytes |
| Approximate separate-process RSS delta | 4,947,968 bytes |
| XCTest process maximum RSS | 61,915,136 bytes |

The copy model is explicit:

1. Rust writes encoded fields into one temporary bounded vector.
2. Rust performs one `copy_nonoverlapping` pass into the caller-owned buffer:
   1,000 operations / 38,400,000 bytes per sample.
3. The disposable Swift wrapper materializes `Array(buffer.prefix(...))`:
   another 1,000 operations / 38,400,000 bytes per sample.

That is two full-payload copy passes and 76,800,000 copied bytes per sample.
Rust retains zero chunk bytes after `next`. A production facade must revisit
the second Swift copy and measure inside the app; this spike only establishes
that the bounded two-copy candidate is feasible.

## 6. Failures, unsupported checks and residual risk

The following failures are retained rather than rewritten as passes:

- The first independent disposal review rejected the prior evidence record.
  Its gaps motivated the property/race/canary/sanitizer/benchmark additions.
- A full Miri invocation was interrupted while interpreting the deliberately
  large randomized/million-row workload. Seven ownership/race/fault tests then
  passed under Miri; native ASan/TSan retained the full workload.
- SwiftPM AddressSanitizer built the bundle but stalled before XCTest. A process
  sample showed `__asan::InitializeShadowMemory` recursing/spinning through
  `MemoryRangeIsAvailable`, `get_dyld_hdr` and `StaticSpinMutex::LockSlow`.
  Direct `xctest` without preloading the runtime exited 134 with
  `interceptors not installed`; preloading reproduced the initialization stall.
- SwiftPM ThreadSanitizer built the bundle but its test helper exited with
  signal 11 before any XCTest began.
- A bare Command Line Tools Swift test cannot import XCTest on this machine;
  the passing Swift evidence uses full Xcode explicitly.
- External `swiftformat`, `swiftlint`, `cargo-audit` and `cargo-deny` are not
  installed. The spike has no third-party Rust dependency, but production CI
  still needs these policy gates.
- No M1/16 GiB floor machine, Intel/Universal target, production app process,
  MainActor/executor callback, real allocator OOM, wild non-null pointer,
  database driver, network cancellation or distribution runtime was tested.

The exact failed/interrupted sanitizer commands were:

```sh
# Interrupted after it entered the intentionally large property workload.
cargo +nightly miri test --manifest-path rust/Cargo.toml --all-targets -- \
  --test-threads=1

# Built successfully, then stalled before XCTest in ASan initialization.
xcrun swift test -c release --sanitize address \
  --skip testOneMillionTypedRowsStayOrderedAndBoundedByChunkCaps \
  --scratch-path .build-asan

# Direct execution diagnosed late runtime loading; preloading then reproduced
# the ASan initialization stall.
xcrun xctest \
  .build-asan/arm64-apple-macosx/release/DataForgeFFISpikePackageTests.xctest
DYLD_INSERT_LIBRARIES=/Applications/Xcode.app/Contents/Developer/Toolchains/\
XcodeDefault.xctoolchain/usr/lib/clang/17/lib/darwin/\
libclang_rt.asan_osx_dynamic.dylib \
  xcrun xctest \
  .build-asan/arm64-apple-macosx/release/DataForgeFFISpikePackageTests.xctest

# Built successfully, then the SwiftPM test helper reported signal 11.
xcrun swift test -c release --sanitize thread \
  --skip testOneMillionTypedRowsStayOrderedAndBoundedByChunkCaps \
  --scratch-path .build-tsan
```

Rust ASan/TSan and Miri materially reduce the remaining pointer/race risk, but
they do not make the failed Swift sanitizer runtime disappear. Production FFI
work must add a CI host/toolchain where Swift sanitizer integration actually
runs before release.

## 7. Acceptance mapping and recommendation

| DF-M0-001 criterion | Disposition |
| --- | --- |
| One million typed rows within bounded chunks | Met on the named developer host |
| Slow consumer backpressures producer | Met by one-outstanding-chunk pull/ACK state and `NEEDS_ACK` evidence |
| ABI mismatch rejects | Met |
| Cancel at lifecycle/race states | Met for the synchronous fake producer; real driver cancellation remains DF-M0-002 |
| Malformed lengths/stale handles/panic/allocation/canary | Met for the spike contract |
| Copies/RSS/latency recorded | Met with explicit limitations above |
| Sanitizer/ownership/concurrency/property evidence | Met through Rust ASan/TSan, targeted Miri, native property/race and Swift integration; Swift sanitizer host limitation remains recorded |
| Durable report before prototype deletion | Met by this file |

Recommendation: retain the ADR-0008 planning contract—versioned fixed-width C
records, caller-owned destination buffers, opaque generation handles, one
outstanding pull/ACK chunk, hard row/byte caps, stateful cancellation and panic
containment. Do not copy the spike into production. Independent review must
confirm this report before deleting the prototype; the report and ADR remain
after deletion.
