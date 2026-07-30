#!/bin/zsh

set -euo pipefail

readonly script_dir=${0:A:h}
readonly spike_root=${script_dir:h}
test_root=$(mktemp -d /tmp/dataforge-distribution-test.XXXXXX)

cleanup_test_root() {
  if [[ -n ${test_root:-} && -d $test_root ]]; then
    find "$test_root" -depth -delete
  fi
}
trap cleanup_test_root EXIT INT TERM

zsh -n "${script_dir}"/*.sh

cargo fmt --manifest-path "${spike_root}/Cargo.toml" --all -- --check
CARGO_TARGET_DIR="${test_root}/cargo-target" \
RUSTFLAGS='-D warnings' cargo check \
  --manifest-path "${spike_root}/Cargo.toml" \
  --workspace \
  --all-targets
CARGO_TARGET_DIR="${test_root}/cargo-target" cargo clippy \
  --manifest-path "${spike_root}/Cargo.toml" \
  --workspace \
  --all-targets \
  --all-features \
  -- -D warnings
CARGO_TARGET_DIR="${test_root}/cargo-target" cargo test \
  --manifest-path "${spike_root}/Cargo.toml" \
  --workspace \
  --all-features

"${script_dir}/run-evidence.sh" "${test_root}/evidence"

for file in "${test_root}/evidence"/*.json; do
  jq empty "$file"
done
jq -e '
  .summary == {
    pass: 13,
    partial: 6,
    unsupported: 4,
    fail: 0,
    total: 23,
    complete_release_gate_passed: false,
    production_distribution_enabled: false,
    updater_adopted: false
  }
' "${test_root}/evidence/runtime.json" >/dev/null
rg -q '^transient_cleanup=pass$' "${test_root}/evidence/runner-completion.txt"

cleanup_test_root
[[ ! -e $test_root ]]
test_root=''
trap - EXIT INT TERM
