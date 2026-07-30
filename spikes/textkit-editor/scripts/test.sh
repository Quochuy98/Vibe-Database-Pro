#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export LC_ALL=C

if [[ ! -d "${DEVELOPER_DIR}" ]]; then
    echo "Full Xcode developer directory not found: ${DEVELOPER_DIR}" >&2
    exit 1
fi

SCRATCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dataforge-textkit-editor.XXXXXX")"
cleanup() {
    rm -rf "${SCRATCH_ROOT}"
}
trap cleanup EXIT INT TERM

cd "${SPIKE_ROOT}"

echo "== Toolchain =="
xcodebuild -version
xcrun swift --version
sw_vers
sysctl -n hw.model hw.memsize hw.logicalcpu

echo "== Format lint =="
xcrun swift-format lint --strict --recursive Package.swift Sources Tests

echo "== Debug build =="
xcrun swift build \
    --scratch-path "${SCRATCH_ROOT}/debug" \
    -Xswiftc -warnings-as-errors

echo "== Tests =="
xcrun swift test \
    --scratch-path "${SCRATCH_ROOT}/tests" \
    --enable-xctest \
    --disable-swift-testing \
    -Xswiftc -warnings-as-errors

echo "== Release build =="
xcrun swift build \
    --configuration release \
    --scratch-path "${SCRATCH_ROOT}/release" \
    -Xswiftc -warnings-as-errors

SAMPLES="${TEXTKIT_SPIKE_SAMPLES:-10}"
for size in 10 100; do
    echo "== BF-01 ${size} MiB release evidence =="
    /usr/bin/time -l \
        "${SCRATCH_ROOT}/release/release/TextKitEditorEvidence" \
        --size "${size}" \
        --samples "${SAMPLES}"
done
