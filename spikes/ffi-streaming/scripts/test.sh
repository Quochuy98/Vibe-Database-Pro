#!/bin/zsh
set -euo pipefail

SPIKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_MANIFEST="$SPIKE_ROOT/rust/Cargo.toml"
ARTIFACTS="$SPIKE_ROOT/artifacts"
export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET="14.0"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DATAFORGE_SECRET_CANARY="DF_SECRET_CANARY_M0_001_DO_NOT_LOG_7F3A9C"

cd "$SPIKE_ROOT"
mkdir -p "$ARTIFACTS"

run_and_record() {
    local label="$1"
    local output="$2"
    shift 2
    echo "== $label =="
    "$@" 2>&1 | tee "$ARTIFACTS/$output"
}

run_targeted_miri_matrix() {
    local test_name
    for test_name in \
        cancel_and_release_attempts_wait_while_next_holds_registry_lock \
        same_handle_next_cancel_release_races_are_linearizable \
        secret_like_destination_canary_survives_controlled_faults_without_logging \
        malformed_inputs_are_zeroed_and_never_advance_state \
        panic_and_allocation_failures_are_contained \
        stale_handles_cannot_cross_slot_reuse \
        pull_ack_enforces_byte_and_row_caps
    do
        cargo +nightly miri test --quiet --manifest-path "$RUST_MANIFEST" \
            "$test_name" -- --test-threads=1
    done
}

run_rust_asan_matrix() {
    RUSTFLAGS="-Zsanitizer=address" \
    RUSTDOCFLAGS="-Zsanitizer=address" \
    CARGO_TARGET_DIR="$SPIKE_ROOT/.build-rust-asan" \
        cargo +nightly test -Zbuild-std --target aarch64-apple-darwin \
        --manifest-path "$RUST_MANIFEST" --all-targets -- --test-threads=1
}

run_rust_tsan_matrix() {
    RUSTFLAGS="-Zsanitizer=thread" \
    RUSTDOCFLAGS="-Zsanitizer=thread" \
    CARGO_TARGET_DIR="$SPIKE_ROOT/.build-rust-tsan" \
        cargo +nightly test -Zbuild-std --target aarch64-apple-darwin \
        --manifest-path "$RUST_MANIFEST" --all-targets -- --test-threads=1
}

run_and_record "Rust format" rust-format.txt \
    cargo fmt --manifest-path "$RUST_MANIFEST" -- --check

run_and_record "C header syntax/layout" c-header.txt \
    clang -std=c11 -Wall -Wextra -Werror -I "$SPIKE_ROOT/include" \
    -fsyntax-only "$SPIKE_ROOT/include/shim.c"

run_and_record "Rust clippy" rust-clippy.txt \
    cargo clippy --manifest-path "$RUST_MANIFEST" --all-targets -- -D warnings

run_and_record "Rust tests" rust-tests.txt \
    cargo test --manifest-path "$RUST_MANIFEST" --all-targets -- --test-threads=1

run_and_record "Targeted Miri ownership/race matrix" rust-miri.txt \
    run_targeted_miri_matrix

run_and_record "Rust AddressSanitizer matrix" rust-asan.txt \
    run_rust_asan_matrix

run_and_record "Rust ThreadSanitizer matrix" rust-tsan.txt \
    run_rust_tsan_matrix

run_and_record "Rust release library" rust-release-build.txt \
    cargo build --manifest-path "$RUST_MANIFEST" --release

run_and_record "Static library architecture" static-library-architecture.txt \
    file "$SPIKE_ROOT/rust/target/release/libdataforge_ffi_spike.a"

run_and_record "Swift release integration" swift-test-release.txt \
    xcrun swift test -c release --scratch-path "$SPIKE_ROOT/.build-xcode"

{
    echo "UNSUPPORTED on this host/toolchain: Swift ASan runtime stalls during shadow-memory initialization."
    echo "UNSUPPORTED on this host/toolchain: Swift TSan bundle exits with signal 11 before XCTest starts."
    echo "Exact attempted commands and diagnostics are retained in the permanent DF-M0-001 report."
} | tee "$ARTIFACTS/swift-sanitizer-runtime-status.txt"

run_and_record "xcodebuild package build" xcodebuild-build.txt \
    xcodebuild -scheme DataForgeFFISpike-Package \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$SPIKE_ROOT/.build-xcodebuild" -quiet build

run_and_record "xcodebuild package test" xcodebuild-test.txt \
    xcodebuild -scheme DataForgeFFISpike-Package \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$SPIKE_ROOT/.build-xcodebuild" -quiet test

run_and_record "Swift release benchmark build" swift-benchmark-build.txt \
    xcrun swift build -c release --product DataForgeFFIBenchmark \
    --scratch-path "$SPIKE_ROOT/.build-xcode"

TEST_BUNDLE="$SPIKE_ROOT/.build-xcode/arm64-apple-macosx/release/DataForgeFFISpikePackageTests.xctest"
run_and_record "Swift runtime RSS (post-build test bundle)" swift-runtime-rss.txt \
    /usr/bin/time -l xcrun xctest "$TEST_BUNDLE"

BENCHMARK="$SPIKE_ROOT/.build-xcode/arm64-apple-macosx/release/DataForgeFFIBenchmark"
run_and_record "Swift benchmark idle RSS baseline" benchmark-idle-rss.txt \
    /usr/bin/time -l "$BENCHMARK" --idle
run_and_record "Swift benchmark: one warm-up plus ten samples" benchmark-results.txt \
    /usr/bin/time -l "$BENCHMARK"

if grep -R -F -q "$DATAFORGE_SECRET_CANARY" "$ARTIFACTS"; then
    echo "Secret-like canary was emitted into an evidence artifact" >&2
    exit 1
fi
echo "PASS: secret-like canary absent from every captured evidence artifact" \
    | tee "$ARTIFACTS/secret-canary-scan.txt"

echo "== Final registry check is asserted by the Swift suite =="
