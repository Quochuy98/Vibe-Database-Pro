#!/bin/zsh

set -euo pipefail

readonly script_dir=${0:A:h}
readonly spike_root=${script_dir:h}
test_root=$(mktemp -d /tmp/dataforge-persistence-keychain-test.XXXXXX)

cleanup_test_root() {
  if [[ -n ${test_root:-} && -d ${test_root:-} ]]; then
    find "$test_root" -depth -delete
  fi
}
trap cleanup_test_root EXIT
trap 'cleanup_test_root; trap - EXIT; exit 130' INT
trap 'cleanup_test_root; trap - EXIT; exit 143' TERM

zsh -n "${script_dir}"/*.sh
xcrun swift-format lint --strict --recursive \
  "${spike_root}/Package.swift" \
  "${spike_root}/Sources" \
  "${spike_root}/Tests"

"${script_dir}/run-evidence.sh" "${test_root}/evidence"

for file in "${test_root}/evidence"/*.json; do
  jq empty "$file"
done

jq -e '
  .summary.total == 20
  and .summary.fail == 0
  and .summary.complete_keychain_gate_passed == false
  and .summary.production_dependency_adopted == false
  and .summary.production_persistence_enabled == false
  and any(.scenarios[]; .id == "MG-02" and .status == "pass")
  and any(.scenarios[]; .id == "TX-01" and .status == "pass")
  and any(.scenarios[]; .id == "CR-01" and .status == "pass")
  and any(.scenarios[]; .id == "SC-01" and .status == "pass")
  and any(.scenarios[]; .id == "CL-01" and .status == "pass")
' "${test_root}/evidence/runtime.json" >/dev/null

jq -e '
  [.connection_profiles[], .query_history[], .workspaces[]]
  | map(ascii_downcase)
  | all(.[];
      test("password|passphrase|private_key|api_key|access_token|refresh_token|client_secret|secret_value")
      | not)
' "${test_root}/evidence/schema.json" >/dev/null

rg -q '^outer_secret_scan=pass$' "${test_root}/evidence/runner-completion.txt"
rg -q '^transient_cleanup=pass$' "${test_root}/evidence/runner-completion.txt"

cleanup_test_root
[[ ! -e $test_root ]]
test_root=''
trap - EXIT INT TERM
