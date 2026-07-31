#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "usage: run-evidence.sh ABSOLUTE_EMPTY_OUTPUT_DIRECTORY"
  exit 64
fi

readonly output_dir=$1
readonly script_dir=${0:A:h}
readonly spike_root=${script_dir:h}
readonly repository_root=$(git -C "$spike_root" rev-parse --show-toplevel)
readonly grdb_version=7.11.1
readonly grdb_revision=b83108d10f42680d78f23fe4d4d80fc88dab3212
readonly grdb_license_sha256=9853f9dce81365fcc1d9b46004633354450164b8d17904e92e80c444545f7e87

if [[ $output_dir != /* ]]; then
  print -u2 "output directory must be absolute"
  exit 64
fi

if [[ ${DATAFORGE_REQUIRE_CLEAN:-0} == 1 ]] &&
  [[ -n $(git -C "$repository_root" status --short) ]]; then
  print -u2 "exact evidence requires a clean worktree"
  exit 65
fi

if [[ -e $output_dir ]] &&
  [[ -n $(find "$output_dir" -mindepth 1 -print -quit 2>/dev/null) ]]; then
  print -u2 "output directory must be empty"
  exit 73
fi

umask 077
mkdir -p "$output_dir"
chmod 0700 "$output_dir"
run_dir=$(mktemp -d /tmp/dataforge-persistence-keychain-run.XXXXXX)
chmod 0700 "$run_dir"

probe=''
keychain_service=''

cleanup_run() {
  if [[ -n ${probe:-} && -x ${probe:-} && -n ${keychain_service:-} ]]; then
    "$probe" cleanup-keychain --service "$keychain_service" >/dev/null 2>&1 || true
  fi
  if [[ -n ${run_dir:-} && -d ${run_dir:-} ]]; then
    find "$run_dir" -depth -delete
  fi
}
trap cleanup_run EXIT
trap 'cleanup_run; trap - EXIT; exit 130' INT
trap 'cleanup_run; trap - EXIT; exit 143' TERM

readonly scratch_path="${run_dir}/scratch"
readonly cache_path="${run_dir}/cache"
readonly fixture_root="${run_dir}/fixture"
readonly secret_file="${run_dir}/canary"
mkdir -p "$scratch_path" "$cache_path" "$fixture_root"
chmod 0700 "$scratch_path" "$cache_path" "$fixture_root"

{
  uuidgen
  uuidgen
} | tr -d '\n-' | tr '[:upper:]' '[:lower:]' >"$secret_file"
chmod 0600 "$secret_file"
keychain_service="com.dataforge.m0-007.$(uuidgen | tr '[:upper:]' '[:lower:]')"

readonly source_commit=$(git -C "$repository_root" rev-parse HEAD)
readonly source_tree=$(git -C "$repository_root" rev-parse HEAD:spikes/persistence-keychain)
readonly source_archive_sha256=$(
  git -C "$repository_root" archive HEAD:spikes/persistence-keychain |
    shasum -a 256 | awk '{print $1}'
)

(
  cd "$spike_root"
  swift package resolve \
    --disable-dependency-cache \
    --scratch-path "$scratch_path" \
    --cache-path "$cache_path" \
    >"${run_dir}/resolve.log" 2>&1
)

jq -e --arg revision "$grdb_revision" --arg version "$grdb_version" '
  .pins == [{
    identity: "grdb.swift",
    kind: "remoteSourceControl",
    location: "https://github.com/groue/GRDB.swift.git",
    state: {revision: $revision, version: $version}
  }]
' "${spike_root}/Package.resolved" >/dev/null

swift build \
  --package-path "$spike_root" \
  --configuration release \
  --scratch-path "$scratch_path" \
  --cache-path "$cache_path" \
  -Xswiftc -warnings-as-errors \
  >"${run_dir}/build.log" 2>&1

readonly bin_path=$(swift build \
  --package-path "$spike_root" \
  --configuration release \
  --scratch-path "$scratch_path" \
  --cache-path "$cache_path" \
  --show-bin-path)
probe="${bin_path}/dataforge-persistence-keychain-probe"
[[ -x $probe ]]

xctest_exit=0
swift test \
  --package-path "$spike_root" \
  --scratch-path "$scratch_path" \
  --cache-path "$cache_path" \
  -Xswiftc -warnings-as-errors \
  >"${run_dir}/swift-test.log" 2>&1 || xctest_exit=$?
readonly xctest_exit
xctest_available=true
if [[ $xctest_exit -ne 0 ]]; then
  rg -q "no such module 'XCTest'" "${run_dir}/swift-test.log"
  xctest_available=false
fi
readonly xctest_available

readonly baseline="${run_dir}/baseline"
swiftc \
  -O \
  -warnings-as-errors \
  -target arm64-apple-macosx14.0 \
  "${spike_root}/Sources/Baseline/main.swift" \
  -o "$baseline"

readonly probe_archs=$(lipo -archs "$probe")
readonly baseline_archs=$(lipo -archs "$baseline")
[[ $probe_archs == arm64 ]]
[[ $baseline_archs == arm64 ]]
otool -l "$probe" | rg -A4 'LC_BUILD_VERSION' | rg -q 'minos 14\.0'
otool -l "$baseline" | rg -A4 'LC_BUILD_VERSION' | rg -q 'minos 14\.0'

"$probe" run \
  --root "$fixture_root" \
  --secret-file "$secret_file" \
  --service "$keychain_service" \
  >"${run_dir}/probe.json" \
  2>"${run_dir}/probe.stderr"
jq empty "${run_dir}/probe.json"
[[ ! -s "${run_dir}/probe.stderr" ]]

cleanup_exit=0
"$probe" cleanup-keychain --service "$keychain_service" \
  >"${run_dir}/cleanup.stdout" \
  2>"${run_dir}/cleanup.stderr" || cleanup_exit=$?
readonly cleanup_exit
[[ ! -s "${run_dir}/cleanup.stdout" ]]
if [[ $cleanup_exit -eq 0 ]]; then
  [[ ! -s "${run_dir}/cleanup.stderr" ]]
else
  [[ $cleanup_exit -eq 1 ]]
  rg -q '^DF-M0-007 probe failed: keychain-missing-entitlement$' \
    "${run_dir}/cleanup.stderr"
  jq -e '
    any(.scenarios[];
      .id == "KC-01"
      and .status == "unsupported"
      and .observation.status_category == "missing-entitlement"
      and .observation.final_missing_verified == "true")
  ' "${run_dir}/probe.json" >/dev/null
fi

readonly checkout="${scratch_path}/checkouts/GRDB.swift"
[[ $(git -C "$checkout" rev-parse HEAD) == "$grdb_revision" ]]
readonly grdb_archive_sha256=$(
  git -C "$checkout" archive "$grdb_revision" |
    shasum -a 256 | awk '{print $1}'
)
readonly observed_license_sha256=$(shasum -a 256 "${checkout}/LICENSE" | awk '{print $1}')
[[ $observed_license_sha256 == "$grdb_license_sha256" ]]

swift package \
  --package-path "$spike_root" \
  --scratch-path "$scratch_path" \
  show-dependencies --format json \
  | jq '
      def clean:
        {
          identity,
          name,
          url: (if .identity == "persistence-keychain" then "<local-spike>" else .url end),
          version,
          dependencies: [.dependencies[] | clean]
        };
      clean
    ' >"${output_dir}/package-graph.json"

curl --fail --silent --show-error --location \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2026-03-10' \
  "https://api.github.com/repos/groue/GRDB.swift/releases/tags/v${grdb_version}" \
  >"${run_dir}/grdb-release-raw.json"
readonly release_tag=$(jq -r '.tag_name' "${run_dir}/grdb-release-raw.json")
readonly release_published_at=$(jq -r '.published_at' "${run_dir}/grdb-release-raw.json")
[[ $release_tag == "v${grdb_version}" ]]

curl --fail --silent --show-error --location \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2026-03-10' \
  'https://api.github.com/repos/groue/GRDB.swift/security-advisories?per_page=100' \
  | jq '[.[] | {
      ghsa_id,
      cve_id,
      severity,
      published_at,
      updated_at,
      withdrawn_at,
      vulnerabilities: [.vulnerabilities[] | {
        package: .package.name,
        vulnerable_version_range,
        patched_versions
      }]
    }]' >"${output_dir}/grdb-advisories.json"

readonly swift_version=$(swiftc --version 2>&1 | head -1)
readonly spm_version=$(swift package --version 2>&1 | head -1)
readonly sqlite_version=$(sqlite3 --version | awk '{print $1}')
readonly os_version=$(sw_vers -productVersion)
readonly os_build=$(sw_vers -buildVersion)
readonly host_arch=$(uname -m)
readonly model_identifier=$(
  system_profiler SPHardwareDataType 2>/dev/null |
    awk -F: '/Model Identifier/{gsub(/^[[:space:]]+/, "", $2); print $2; exit}'
)
readonly memory_bytes=$(sysctl -n hw.memsize)
readonly logical_cpu=$(sysctl -n hw.logicalcpu)
readonly developer_dir=$(xcode-select -p 2>&1)
full_xcode_available=false
if xcodebuild -version >"${run_dir}/xcodebuild.log" 2>&1; then
  full_xcode_available=true
fi
readonly full_xcode_available
readonly identity_count=$(
  security find-identity -v -p codesigning 2>/dev/null |
    awk '/valid identities found/{print $1}'
)

readonly probe_bytes=$(stat -f %z "$probe")
readonly baseline_bytes=$(stat -f %z "$baseline")
readonly size_delta_bytes=$((probe_bytes - baseline_bytes))
readonly probe_sha256=$(shasum -a 256 "$probe" | awk '{print $1}')
readonly baseline_sha256=$(shasum -a 256 "$baseline" | awk '{print $1}')

jq -n \
  --arg source_commit "$source_commit" \
  --arg source_tree "$source_tree" \
  --arg source_archive_sha256 "$source_archive_sha256" \
  --arg model_identifier "$model_identifier" \
  --arg host_arch "$host_arch" \
  --arg os_version "$os_version" \
  --arg os_build "$os_build" \
  --arg developer_dir "$developer_dir" \
  --arg swift "$swift_version" \
  --arg spm "$spm_version" \
  --arg sqlite "$sqlite_version" \
  --argjson memory_bytes "$memory_bytes" \
  --argjson logical_cpu "$logical_cpu" \
  --argjson full_xcode_available "$full_xcode_available" \
  --argjson xctest_available "$xctest_available" \
  --argjson xctest_exit "$xctest_exit" \
  --argjson identity_count "$identity_count" \
  '{
    source: {
      commit: $source_commit,
      tree: $source_tree,
      archive_sha256: $source_archive_sha256
    },
    host: {
      model_identifier: $model_identifier,
      architecture: $host_arch,
      memory_bytes: $memory_bytes,
      logical_cpu: $logical_cpu,
      os_version: $os_version,
      os_build: $os_build
    },
    toolchain: {
      developer_directory: $developer_dir,
      full_xcode_available: $full_xcode_available,
      swift: $swift,
      swift_package_manager: $spm,
      system_sqlite: $sqlite,
      xctest_available: $xctest_available,
      swift_test_exit: $xctest_exit
    },
    signing_environment: {
      valid_codesigning_identity_count: $identity_count,
      identity_names_enumerated: false,
      keychain_paths_enumerated: false
    }
  }' >"${output_dir}/environment.json"

jq -n \
  --arg version "$grdb_version" \
  --arg revision "$grdb_revision" \
  --arg published_at "$release_published_at" \
  --arg archive_sha256 "$grdb_archive_sha256" \
  --arg license_sha256 "$observed_license_sha256" \
  --arg sqlite_version "$sqlite_version" \
  --arg probe_sha256 "$probe_sha256" \
  --arg baseline_sha256 "$baseline_sha256" \
  --argjson probe_bytes "$probe_bytes" \
  --argjson baseline_bytes "$baseline_bytes" \
  --argjson size_delta_bytes "$size_delta_bytes" \
  --slurpfile advisories "${output_dir}/grdb-advisories.json" \
  '{
    candidate: "GRDB",
    version: $version,
    revision: $revision,
    published_at: $published_at,
    source_archive_sha256: $archive_sha256,
    license: {
      preliminary: "MIT; final application and notice review still required",
      license_file_sha256: $license_sha256,
      legal_approval: false
    },
    advisories: $advisories[0],
    package_graph: {
      normal_external_dependencies: 1,
      grdb_normal_dependencies: 0,
      system_library: "SQLite",
      system_sqlite_version: $sqlite_version
    },
    requirements: {
      swift: "6.1 or newer",
      xcode: "16.3 or newer for XCTest/Xcode lane",
      macos: "10.15 or newer upstream; spike target 14.0",
      sqlite: "3.20 or newer"
    },
    binary_evidence: {
      architecture: "arm64",
      probe_sha256: $probe_sha256,
      probe_bytes: $probe_bytes,
      baseline_sha256: $baseline_sha256,
      baseline_bytes: $baseline_bytes,
      size_delta_bytes: $size_delta_bytes
    },
    replacement: {
      boundary: "Swift metadata persistence port",
      alternatives: ["SQLite C API", "another reviewed Swift SQLite wrapper"],
      migration_and_query_rewrite_required: true
    },
    adoption_approved: false
  }' >"${output_dir}/grdb-candidate.json"

jq '.schema' "${run_dir}/probe.json" >"${output_dir}/schema.json"

ps -axo command >"${run_dir}/process-snapshot.txt"
if rg --hidden --text --quiet --fixed-strings --file "$secret_file" "$output_dir"; then
  print -u2 "secret canary reached retained evidence"
  exit 1
fi

while IFS= read -r -d '' file; do
  if rg --text --quiet --fixed-strings --file "$secret_file" "$file"; then
    print -u2 "secret canary reached a transient file outside the owned canary"
    exit 1
  fi
done < <(find "$fixture_root" -type f -print0)

for file in \
  "${run_dir}/probe.json" \
  "${run_dir}/probe.stderr" \
  "${run_dir}/cleanup.stdout" \
  "${run_dir}/cleanup.stderr" \
  "${run_dir}/process-snapshot.txt" \
  "${run_dir}/resolve.log" \
  "${run_dir}/build.log" \
  "${run_dir}/swift-test.log"; do
  if rg --text --quiet --fixed-strings --file "$secret_file" "$file"; then
    print -u2 "secret canary reached a transient log, output, or process snapshot"
    exit 1
  fi
done

if git -C "$repository_root" grep -I -F -f "$secret_file" -- . >/dev/null 2>&1; then
  print -u2 "secret canary reached Git-tracked content"
  exit 1
fi

if rg --quiet '/Users/|/private/tmp/|/tmp/dataforge-' "$output_dir"; then
  print -u2 "retained evidence contains a personal or transient absolute path"
  exit 1
fi

readonly probe_report=$(jq -c '.' "${run_dir}/probe.json")
cleanup_run
[[ ! -e $run_dir ]]
run_dir=''
probe=''
keychain_service=''
trap - EXIT INT TERM

jq -n \
  --argjson probe "$probe_report" \
  --argjson xctest_available "$xctest_available" \
  --argjson size_delta_bytes "$size_delta_bytes" \
  --argjson cleanup_exit "$cleanup_exit" \
  '
    def scenario($id; $status; $observation):
      {id: $id, status: $status, observation: $observation};
    ($probe.scenarios + [
      scenario("EN-01"; "pass"; {
        host_and_tool_inventory_recorded: "true",
        environment_dumped: "false",
        xctest_available: ($xctest_available | tostring)
      }),
      scenario("SC-01"; "pass"; {
        canary_absent_from_retained_transient_git_and_process_surfaces: "true"
      }),
      scenario("DP-01"; "pass"; {
        exact_revision_license_advisories_graph_requirements_arm64_size_replacement_recorded: "true",
        size_delta_bytes: ($size_delta_bytes | tostring),
        adoption_approved: "false"
      }),
      scenario("CL-01"; "pass"; {
        keychain_final_missing_verified_by_probe: "true",
        outer_cleanup_exit: ($cleanup_exit | tostring),
        transient_directory_removed: "true"
      })]) as $scenarios
    | {
        schemaVersion: 1,
        evidenceKind: "developer-host-disposable-persistence-keychain-spike",
        scenarios: ($scenarios | sort_by(.id)),
        measurements: $probe.measurements,
        summary: {
          pass: ([$scenarios[] | select(.status == "pass")] | length),
          partial: ([$scenarios[] | select(.status == "partial")] | length),
          unsupported: ([$scenarios[] | select(.status == "unsupported")] | length),
          fail: ([$scenarios[] | select(.status == "fail")] | length),
          total: ($scenarios | length),
          complete_keychain_gate_passed: false,
          production_dependency_adopted: false,
          production_persistence_enabled: false
        }
      }
  ' >"${output_dir}/runtime.json"

jq empty "${output_dir}"/*.json
if rg --quiet '/Users/|/private/tmp/|/tmp/dataforge-' "$output_dir"; then
  print -u2 "final retained evidence contains a personal or transient absolute path"
  exit 1
fi

print 'outer_secret_scan=pass' >"${output_dir}/runner-completion.txt"
print 'transient_cleanup=pass' >>"${output_dir}/runner-completion.txt"
print 'complete_keychain_gate_passed=false' >>"${output_dir}/runner-completion.txt"

readonly pass_count=$(jq -r '.summary.pass' "${output_dir}/runtime.json")
readonly partial_count=$(jq -r '.summary.partial' "${output_dir}/runtime.json")
readonly unsupported_count=$(jq -r '.summary.unsupported' "${output_dir}/runtime.json")
readonly fail_count=$(jq -r '.summary.fail' "${output_dir}/runtime.json")
print "DF-M0-007 evidence complete: ${pass_count} pass, ${partial_count} partial, ${unsupported_count} unsupported, ${fail_count} fail"
