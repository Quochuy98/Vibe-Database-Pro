#!/bin/zsh
set -euo pipefail

SPIKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_MANIFEST="$SPIKE_ROOT/rust/Cargo.toml"
export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET="14.0"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$SPIKE_ROOT"

echo "== Rust format =="
cargo fmt --manifest-path "$RUST_MANIFEST" -- --check

echo "== C header syntax/layout =="
clang -std=c11 -Wall -Wextra -Werror -I "$SPIKE_ROOT/include" -fsyntax-only "$SPIKE_ROOT/include/shim.c"

echo "== Rust clippy =="
cargo clippy --manifest-path "$RUST_MANIFEST" --all-targets -- -D warnings

echo "== Rust tests =="
cargo test --manifest-path "$RUST_MANIFEST" --all-targets -- --test-threads=1

echo "== Rust release library =="
cargo build --manifest-path "$RUST_MANIFEST" --release

echo "== Static library architecture =="
file "$SPIKE_ROOT/rust/target/release/libdataforge_ffi_spike.a"

echo "== Swift release integration (RSS output is diagnostic only) =="
mkdir -p "$SPIKE_ROOT/artifacts"
xcrun swift test -c release --scratch-path "$SPIKE_ROOT/.build-xcode" 2>&1 \
    | tee "$SPIKE_ROOT/artifacts/swift-test-release.txt"

TEST_BUNDLE="$SPIKE_ROOT/.build-xcode/arm64-apple-macosx/release/DataForgeFFISpikePackageTests.xctest"
echo "== Swift runtime RSS (post-build test bundle) =="
/usr/bin/time -l xcrun xctest "$TEST_BUNDLE" 2>&1 \
    | tee "$SPIKE_ROOT/artifacts/swift-runtime-rss.txt"

echo "== Final registry check is asserted by the Swift suite =="
