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

SCRATCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dataforge-grid-spike.XXXXXX")"
ARTIFACT_ROOT="${GRID_SPIKE_ARTIFACT_DIR:-${SPIKE_ROOT}/artifacts/df-m0-004}"
mkdir -p "${ARTIFACT_ROOT}"
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

echo "== SwiftPM tests =="
xcrun swift test \
    --scratch-path "${SCRATCH_ROOT}/tests" \
    --enable-xctest \
    --disable-swift-testing \
    -Xswiftc -warnings-as-errors

echo "== Native Xcode build and tests =="
xcodebuild \
    -scheme NSTableViewGridSpike-Package \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "${SCRATCH_ROOT}/DerivedData" \
    SUPPORTS_MACCATALYST=NO \
    build test

echo "== Release build =="
xcrun swift build \
    --configuration release \
    --scratch-path "${SCRATCH_ROOT}/release" \
    -Xswiftc -warnings-as-errors

SAMPLES="${GRID_SPIKE_SAMPLES:-10}"
SCROLL_SECONDS="${GRID_SPIKE_SCROLL_SECONDS:-10}"
SOURCE_REVISION="${GRID_SPIKE_SOURCE_REVISION:-$(git rev-parse HEAD)}"

for rows in 1000000 10000000; do
    echo "== BF-02 ${rows} logical rows release evidence =="
    /usr/bin/time -l \
        "${SCRATCH_ROOT}/release/release/grid-evidence" \
        --fixture bf02 \
        --rows "${rows}" \
        --samples "${SAMPLES}" \
        --scroll-seconds "${SCROLL_SECONDS}" \
        --source-revision "${SOURCE_REVISION}" \
        | tee "${ARTIFACT_ROOT}/bf02-${rows}.json"
done

echo "== BF-03 wide-grid release evidence =="
/usr/bin/time -l \
    "${SCRATCH_ROOT}/release/release/grid-evidence" \
    --fixture bf03 \
    --rows 100000 \
    --samples "${SAMPLES}" \
    --scroll-seconds "${SCROLL_SECONDS}" \
    --source-revision "${SOURCE_REVISION}" \
    | tee "${ARTIFACT_ROOT}/bf03-100000.json"
