#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly SPIKE_DIRECTORY="${SCRIPT_DIRECTORY:h}"
readonly ARTIFACT_DIRECTORY="${SPIKE_DIRECTORY}/artifacts/df-m0-005"

cd "$SPIKE_DIRECTORY"

cargo fmt --all -- --check
RUSTFLAGS='-D warnings' cargo check --workspace --all-targets
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo audit
cargo deny check

if cargo tree -p dataforge-russh-probe -e normal | \
    LC_ALL=C grep -E '(^|[[:space:]])(rsa|flate2) v' >/dev/null 2>&1; then
    print -u2 -- 'Minimal russh feature graph unexpectedly contains RSA or compression.'
    exit 70
fi

RUSTFLAGS='-D warnings' cargo build --release --workspace

if /usr/bin/strings target/release/dataforge-russh-probe | LC_ALL=C grep -E \
    'session_write_encrypted, buf|enc: \{|sign_request: \{' >/dev/null 2>&1; then
    print -u2 -- 'Release russh probe retains a sensitive Debug/Trace formatting path.'
    exit 70
fi

typeset architecture="$(/usr/bin/lipo -archs target/release/dataforge-russh-probe)"
if [[ "$architecture" != 'arm64' ]]; then
    print -u2 -- "Unexpected russh probe architecture: ${architecture}."
    exit 70
fi

mkdir -m 0700 -p "$ARTIFACT_DIRECTORY"
{
    print -r -- "russh_probe_architecture=${architecture}"
    print -r -- "russh_probe_bytes=$(stat -f '%z' target/release/dataforge-russh-probe)"
    print -r -- "openssh_probe_bytes=$(stat -f '%z' target/release/dataforge-openssh-probe)"
    print -r -- "system_ssh_bytes=$(stat -f '%z' /usr/bin/ssh)"
} >"${ARTIFACT_DIRECTORY}/build-metrics.txt"
chmod 0600 "${ARTIFACT_DIRECTORY}/build-metrics.txt"

DATAFORGE_TEST_ALLOW_DESTRUCTIVE=1 DATAFORGE_TEST_ENVIRONMENT=test \
    "${SCRIPT_DIRECTORY}/run-evidence.sh"
