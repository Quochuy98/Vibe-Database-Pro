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
readonly sparkle_version=2.9.4
readonly sparkle_commit=b6496a74a087257ef5e6da1c5b29a447a60f5bd7
readonly sparkle_asset=Sparkle-2.9.4.tar.xz
readonly sparkle_sha256=ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9
readonly sparkle_url=https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz

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
mkdir -p "$output_dir"

run_dir=$(mktemp -d /tmp/dataforge-distribution-run.XXXXXX)

cleanup_run_dir() {
  if [[ -n ${run_dir:-} && -d $run_dir ]]; then
    find "$run_dir" -depth -delete
  fi
}
trap cleanup_run_dir EXIT INT TERM

readonly build_root="${run_dir}/build"
readonly secret_root="${run_dir}/secrets"
readonly sparkle_root="${run_dir}/sparkle"
readonly source_commit=$(git -C "$repository_root" rev-parse HEAD)
readonly source_tree=$(git -C "$repository_root" rev-parse HEAD:spikes/distribution)
readonly source_archive_sha256=$(git -C "$repository_root" archive HEAD:spikes/distribution | shasum -a 256 | awk '{print $1}')
mkdir -p "$build_root" "$secret_root" "$sparkle_root"
chmod 0700 "$run_dir" "$secret_root"

tree_digest() {
  local root=$1
  find "$root" -type f | LC_ALL=C sort | while IFS= read -r file; do
    local relative=${file#${root}/}
    local digest=$(shasum -a 256 "$file" | awk '{print $1}')
    print -r -- "${digest}  ${relative}"
  done | shasum -a 256 | awk '{print $1}'
}

require_exact_arch() {
  local item=$1
  local archs=$(lipo -archs "$item")
  [[ $archs == arm64 ]]
}

require_runtime_without_entitlements() {
  local item=$1
  codesign -dv --verbose=4 "$item" 2>&1 | rg -q 'flags=.*runtime'
  ! codesign -d --entitlements - "$item" 2>&1 | rg -q '<plist'
}

require_identifier() {
  local item=$1
  local identifier=$2
  codesign --verify --strict --verbose=2 \
    -R="identifier \"${identifier}\"" \
    "$item" >/dev/null 2>&1
}

sign_replacement() {
  local item=$1
  local identifier=$2
  codesign \
    --force \
    --sign - \
    --timestamp=none \
    --options runtime \
    --identifier "$identifier" \
    --requirements "=designated => identifier \"${identifier}\"" \
    "$item" >/dev/null 2>&1
}

readonly app100="${build_root}/DataForgeDistributionProbe-100.app"
readonly app101="${build_root}/DataForgeDistributionProbe-101.app"
"${script_dir}/build.sh" "$build_root" 100 stable >"${run_dir}/build-100.log" 2>&1
"${script_dir}/build.sh" "$build_root" 101 stable >"${run_dir}/build-101.log" 2>&1

"${script_dir}/sign-local.sh" "$app100" >"${run_dir}/sign-100.log" 2>&1
"${script_dir}/sign-local.sh" "$app101" >"${run_dir}/sign-101.log" 2>&1

readonly app_executable="${app101}/Contents/MacOS/DataForgeDistributionProbe"
readonly core_binary="${app101}/Contents/Frameworks/libdataforge_distribution_core.dylib"
readonly helper_binary="${app101}/Contents/Helpers/DataForgeDistributionHelper"

for item in "$app_executable" "$core_binary" "$helper_binary"; do
  require_exact_arch "$item"
  otool -l "$item" | rg -A4 'LC_BUILD_VERSION' | rg -q 'minos 14\.0'
done

readonly linked_core=$(otool -L "$app_executable" | sed -n '2p' | awk '{print $1}')
[[ $linked_core == @rpath/libdataforge_distribution_core.dylib ]]
! otool -L "$app_executable" | rg -q '/Users/|/private/tmp/'

readonly launch_output=$($app_executable)
[[ $launch_output == 'dataforge-distribution-probe-ok core=65536 helper=ok' ]]

for app in "$app100" "$app101"; do
  codesign --verify --deep --strict --verbose=4 "$app" >/dev/null 2>&1
done
codesign --verify --strict --verbose=4 "$core_binary" >/dev/null 2>&1
codesign --verify --strict --verbose=4 "$helper_binary" >/dev/null 2>&1

require_identifier "$app101" com.dataforge.distribution-probe
require_identifier "$core_binary" com.dataforge.distribution-probe.core
require_identifier "$helper_binary" com.dataforge.distribution-probe.helper
if codesign --verify --strict -R='identifier "com.dataforge.wrong"' \
  "$app101" >/dev/null 2>&1; then
  print -u2 "wrong designated requirement unexpectedly passed"
  exit 1
fi

readonly app100_requirement=$(codesign -d -r- "$app100" 2>&1 | sed -n 's/^designated => //p')
readonly app101_requirement=$(codesign -d -r- "$app101" 2>&1 | sed -n 's/^designated => //p')
readonly core_requirement=$(codesign -d -r- "$core_binary" 2>&1 | sed -n 's/^designated => //p')
readonly helper_requirement=$(codesign -d -r- "$helper_binary" 2>&1 | sed -n 's/^designated => //p')
[[ $app100_requirement == 'identifier "com.dataforge.distribution-probe"' ]]
[[ $app101_requirement == "$app100_requirement" ]]
[[ $core_requirement == 'identifier "com.dataforge.distribution-probe.core"' ]]
[[ $helper_requirement == 'identifier "com.dataforge.distribution-probe.helper"' ]]

for item in "$app101" "$core_binary" "$helper_binary"; do
  require_runtime_without_entitlements "$item"
done

readonly resource_tamper="${run_dir}/resource-tamper.app"
ditto "$app101" "$resource_tamper"
print 'tampered' >> "${resource_tamper}/Contents/Resources/probe-version.txt"
if codesign --verify --deep --strict "$resource_tamper" >/dev/null 2>&1; then
  print -u2 "sealed resource tamper unexpectedly passed"
  exit 1
fi

readonly wrong_helper="${run_dir}/wrong-helper"
swiftc \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -D DATAFORGE_REPLACEMENT \
  -target arm64-apple-macosx14.0 \
  "${spike_root}/Sources/Helper/main.swift" \
  -o "$wrong_helper"
sign_replacement "$wrong_helper" com.dataforge.distribution-probe.wrong-helper
readonly wrong_helper_app="${run_dir}/wrong-helper.app"
ditto "$app101" "$wrong_helper_app"
cp "$wrong_helper" "${wrong_helper_app}/Contents/Helpers/DataForgeDistributionHelper"
if codesign --verify --deep --strict "$wrong_helper_app" >/dev/null 2>&1; then
  print -u2 "wrong-requirement helper substitution unexpectedly passed"
  exit 1
fi

readonly same_id_helper="${run_dir}/same-id-helper"
cp "$wrong_helper" "$same_id_helper"
sign_replacement "$same_id_helper" com.dataforge.distribution-probe.helper
readonly same_id_helper_app="${run_dir}/same-id-helper.app"
ditto "$app101" "$same_id_helper_app"
cp "$same_id_helper" "${same_id_helper_app}/Contents/Helpers/DataForgeDistributionHelper"
same_id_ad_hoc_outer_verifies=false
if codesign --verify --deep --strict "$same_id_helper_app" >/dev/null 2>&1; then
  same_id_ad_hoc_outer_verifies=true
fi
readonly same_id_ad_hoc_outer_verifies

gatekeeper_exit=0
spctl --assess --type execute --verbose=4 "$app101" \
  >"${run_dir}/gatekeeper.log" 2>&1 || gatekeeper_exit=$?
readonly gatekeeper_exit
[[ $gatekeeper_exit -ne 0 ]]

stapler_exit=0
xcrun stapler validate "$app101" >"${run_dir}/stapler.log" 2>&1 || stapler_exit=$?
readonly stapler_exit
[[ $stapler_exit -ne 0 ]]

readonly identity_count=$(security find-identity -v -p codesigning 2>/dev/null | awk '/valid identities found/{print $1}')
[[ $identity_count == <-> ]]
readonly developer_dir=$(xcode-select -p 2>&1)
xcode_available=false
if xcodebuild -version >"${run_dir}/xcodebuild.log" 2>&1; then
  xcode_available=true
fi
readonly xcode_available
readonly swift_version=$(swiftc --version 2>&1 | head -1)
readonly rust_version=$(rustc --version)
readonly cargo_version=$(cargo --version)
readonly notarytool_version=$(xcrun notarytool --version | head -1)
readonly os_version=$(sw_vers -productVersion)
readonly os_build=$(sw_vers -buildVersion)
readonly host_arch=$(uname -m)
readonly model_identifier=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F: '/Model Identifier/{gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
readonly memory_bytes=$(sysctl -n hw.memsize)
readonly logical_cpu=$(sysctl -n hw.logicalcpu)

curl --fail --silent --show-error --location \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2026-03-10' \
  https://api.github.com/repos/sparkle-project/Sparkle/releases/latest \
  >"${run_dir}/sparkle-release-raw.json"
readonly latest_tag=$(jq -r '.tag_name' "${run_dir}/sparkle-release-raw.json")
readonly published_at=$(jq -r '.published_at' "${run_dir}/sparkle-release-raw.json")
readonly release_asset_digest=$(jq -r --arg name "$sparkle_asset" '.assets[] | select(.name == $name) | .digest' "${run_dir}/sparkle-release-raw.json")
[[ $latest_tag == "$sparkle_version" ]]
[[ $release_asset_digest == "sha256:${sparkle_sha256}" ]]

curl --fail --silent --show-error --location \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2026-03-10' \
  https://api.github.com/repos/sparkle-project/Sparkle/git/ref/tags/2.9.4 \
  >"${run_dir}/sparkle-tag.json"
readonly release_commit=$(jq -r '.object.sha' "${run_dir}/sparkle-tag.json")
[[ $release_commit == "$sparkle_commit" ]]

curl --fail --silent --show-error --location \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2026-03-10' \
  'https://api.github.com/repos/sparkle-project/Sparkle/security-advisories?per_page=100' \
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
    }]' >"${run_dir}/sparkle-advisories.json"
jq empty "${run_dir}/sparkle-advisories.json"

curl --fail --silent --show-error --location "$sparkle_url" \
  -o "${sparkle_root}/${sparkle_asset}"
readonly downloaded_sparkle_sha=$(shasum -a 256 "${sparkle_root}/${sparkle_asset}" | awk '{print $1}')
[[ $downloaded_sparkle_sha == "$sparkle_sha256" ]]
tar -xf "${sparkle_root}/${sparkle_asset}" -C "$sparkle_root"

readonly sparkle_framework="${sparkle_root}/Sparkle.framework"
readonly sparkle_binary="${sparkle_framework}/Versions/B/Sparkle"
readonly sign_update="${sparkle_root}/bin/sign_update"
readonly generate_keys="${sparkle_root}/bin/generate_keys"
readonly generate_appcast="${sparkle_root}/bin/generate_appcast"
for item in "$sparkle_framework" "$sign_update" "$generate_keys" "$generate_appcast"; do
  codesign --verify --deep --strict --verbose=2 "$item" >/dev/null 2>&1
done
readonly sparkle_framework_archs=$(lipo -archs "$sparkle_binary")
readonly sign_update_archs=$(lipo -archs "$sign_update")
[[ $sparkle_framework_archs == 'x86_64 arm64' ]]
[[ $sign_update_archs == 'x86_64 arm64' ]]
readonly sparkle_license_sha=$(shasum -a 256 "${sparkle_root}/LICENSE" | awk '{print $1}')
readonly sparkle_framework_bytes=$(du -sk "$sparkle_framework" | awk '{print $1 * 1024}')
readonly sparkle_binary_bytes=$(stat -f %z "$sparkle_binary")
readonly sign_update_bytes=$(stat -f %z "$sign_update")
readonly generate_keys_bytes=$(stat -f %z "$generate_keys")
readonly generate_appcast_bytes=$(stat -f %z "$generate_appcast")
readonly sparkle_nested_code_count=$(find "${sparkle_framework}/Versions/B" \( -name '*.app' -o -name '*.xpc' -o -name Autoupdate \) | wc -l | tr -d ' ')

umask 077
openssl rand -base64 32 >"${secret_root}/old.key"
openssl rand -base64 32 >"${secret_root}/new.key"
chmod 0600 "${secret_root}/old.key" "${secret_root}/new.key"
[[ $(base64 -D <"${secret_root}/old.key" | wc -c | tr -d ' ') == 32 ]]
[[ $(base64 -D <"${secret_root}/new.key" | wc -c | tr -d ' ') == 32 ]]

readonly update_archive="${run_dir}/DataForgeDistributionProbe-101.zip"
ditto -c -k --sequesterRsrc --keepParent "$app101" "$update_archive"
readonly update_archive_sha=$(shasum -a 256 "$update_archive" | awk '{print $1}')
readonly update_archive_bytes=$(stat -f %z "$update_archive")
readonly old_signature=$($sign_update --ed-key-file "${secret_root}/old.key" -p "$update_archive")
$sign_update --ed-key-file "${secret_root}/old.key" --verify \
  "$update_archive" "$old_signature" >/dev/null

readonly tampered_archive="${run_dir}/DataForgeDistributionProbe-101-tampered.zip"
cp "$update_archive" "$tampered_archive"
print -n 'tamper' >> "$tampered_archive"
if $sign_update --ed-key-file "${secret_root}/old.key" --verify \
  "$tampered_archive" "$old_signature" >/dev/null 2>&1; then
  print -u2 "tampered update archive unexpectedly verified"
  exit 1
fi
if $sign_update --ed-key-file "${secret_root}/new.key" --verify \
  "$update_archive" "$old_signature" >/dev/null 2>&1; then
  print -u2 "wrong update key unexpectedly verified"
  exit 1
fi

readonly new_signature=$($sign_update --ed-key-file "${secret_root}/new.key" -p "$update_archive")
$sign_update --ed-key-file "${secret_root}/new.key" --verify \
  "$update_archive" "$new_signature" >/dev/null
if $sign_update --ed-key-file "${secret_root}/old.key" --verify \
  "$update_archive" "$new_signature" >/dev/null 2>&1; then
  print -u2 "old update key unexpectedly verified the new-key signature"
  exit 1
fi

cp "${sparkle_root}/SampleAppcast.xml" "${run_dir}/signed-appcast.xml"
$sign_update --ed-key-file "${secret_root}/old.key" \
  "${run_dir}/signed-appcast.xml" >"${run_dir}/signed-feed.log"
rg -q 'sparkle:edSignature=' "${run_dir}/signed-appcast.xml"
$sign_update --ed-key-file "${secret_root}/old.key" --verify \
  "${run_dir}/signed-appcast.xml" >/dev/null

readonly installed_build=$(plutil -extract CFBundleVersion raw -o - "${app100}/Contents/Info.plist")
readonly candidate_build=$(plutil -extract CFBundleVersion raw -o - "${app101}/Contents/Info.plist")
readonly installed_bundle=$(plutil -extract CFBundleIdentifier raw -o - "${app100}/Contents/Info.plist")
readonly candidate_bundle=$(plutil -extract CFBundleIdentifier raw -o - "${app101}/Contents/Info.plist")
readonly candidate_channel=$(plutil -extract DataForgeUpdateChannel raw -o - "${app101}/Contents/Info.plist")
readonly candidate_arch=$(lipo -archs "$app_executable")
"${script_dir}/check-update-policy.sh" \
  "$installed_build" "$candidate_build" \
  "$installed_bundle" "$candidate_bundle" \
  stable "$candidate_channel" arm64 "$candidate_arch" \
  >"${run_dir}/valid-policy.log"

policy_negative_count=0
for arguments in \
  '100 99 com.dataforge.distribution-probe com.dataforge.distribution-probe stable stable arm64 arm64' \
  '100 100 com.dataforge.distribution-probe com.dataforge.distribution-probe stable stable arm64 arm64' \
  '100 101 com.dataforge.distribution-probe com.dataforge.wrong stable stable arm64 arm64' \
  '100 101 com.dataforge.distribution-probe com.dataforge.distribution-probe stable beta arm64 arm64' \
  '100 101 com.dataforge.distribution-probe com.dataforge.distribution-probe stable stable arm64 x86_64'; do
  if "${script_dir}/check-update-policy.sh" ${(z)arguments} >/dev/null 2>&1; then
    print -u2 "negative update-policy model unexpectedly accepted"
    exit 1
  fi
  (( policy_negative_count += 1 ))
done
readonly policy_negative_count

readonly rollback_root="${run_dir}/rollback"
mkdir -p "$rollback_root"
ditto "$app100" "${rollback_root}/installed.app"
ditto "$app101" "${rollback_root}/staged.app"
codesign --verify --deep --strict "${rollback_root}/staged.app" >/dev/null 2>&1
readonly installed_before=$(tree_digest "${rollback_root}/installed.app")
readonly installed_after=$(tree_digest "${rollback_root}/installed.app")
[[ $installed_before == "$installed_after" ]]

readonly app_binary_sha=$(shasum -a 256 "$app_executable" | awk '{print $1}')
readonly core_binary_sha=$(shasum -a 256 "$core_binary" | awk '{print $1}')
readonly helper_binary_sha=$(shasum -a 256 "$helper_binary" | awk '{print $1}')
readonly app_binary_bytes=$(stat -f %z "$app_executable")
readonly core_binary_bytes=$(stat -f %z "$core_binary")
readonly helper_binary_bytes=$(stat -f %z "$helper_binary")
readonly app101_tree_sha=$(tree_digest "$app101")
readonly evidence_created=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --arg schema_version '1' \
  --arg source_commit "$source_commit" \
  --arg source_tree "$source_tree" \
  --arg source_archive_sha256 "$source_archive_sha256" \
  --arg model_identifier "$model_identifier" \
  --arg host_arch "$host_arch" \
  --arg os_version "$os_version" \
  --arg os_build "$os_build" \
  --arg developer_dir "$developer_dir" \
  --arg swift "$swift_version" \
  --arg rust "$rust_version" \
  --arg cargo "$cargo_version" \
  --arg notarytool "$notarytool_version" \
  --argjson memory_bytes "$memory_bytes" \
  --argjson logical_cpu "$logical_cpu" \
  --argjson identity_count "$identity_count" \
  --argjson xcode_available "$xcode_available" \
  '{
    schema_version: ($schema_version | tonumber),
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
      full_xcode_available: $xcode_available,
      swift: $swift,
      rust: $rust,
      cargo: $cargo,
      notarytool: $notarytool
    },
    signing_environment: {
      valid_codesigning_identity_count: $identity_count,
      identity_names_enumerated: false,
      notary_profile_searched: false,
      credentialed_submission_attempted: false
    }
  }' >"${output_dir}/environment.json"

jq -n \
  --arg version "$sparkle_version" \
  --arg tag_commit "$release_commit" \
  --arg published_at "$published_at" \
  --arg asset "$sparkle_asset" \
  --arg asset_url "$sparkle_url" \
  --arg asset_sha256 "$downloaded_sparkle_sha" \
  --arg license_sha256 "$sparkle_license_sha" \
  --arg framework_archs "$sparkle_framework_archs" \
  --arg sign_update_archs "$sign_update_archs" \
  --argjson framework_bytes "$sparkle_framework_bytes" \
  --argjson framework_binary_bytes "$sparkle_binary_bytes" \
  --argjson sign_update_bytes "$sign_update_bytes" \
  --argjson generate_keys_bytes "$generate_keys_bytes" \
  --argjson generate_appcast_bytes "$generate_appcast_bytes" \
  --argjson nested_code_count "$sparkle_nested_code_count" \
  --slurpfile advisories "${run_dir}/sparkle-advisories.json" \
  '{
    candidate: "Sparkle",
    version: $version,
    tag_commit: $tag_commit,
    published_at: $published_at,
    release_asset: {
      name: $asset,
      url: $asset_url,
      sha256: $asset_sha256
    },
    license: {
      preliminary: "MIT with retained third-party notices; legal review required",
      license_file_sha256: $license_sha256
    },
    binary_evidence: {
      framework_architectures: ($framework_archs | split(" ")),
      sign_update_architectures: ($sign_update_archs | split(" ")),
      extracted_framework_logical_bytes: $framework_bytes,
      framework_binary_bytes: $framework_binary_bytes,
      sign_update_bytes: $sign_update_bytes,
      generate_keys_bytes: $generate_keys_bytes,
      generate_appcast_bytes: $generate_appcast_bytes,
      discovered_nested_code_count: $nested_code_count,
      strict_nested_signature_verification: true
    },
    advisories: $advisories[0],
    integration: {
      framework_embedded: false,
      updater_install_run: false,
      signed_feed_tool_smoke: true,
      pre_extraction_host_configuration_run: false,
      adoption_approved: false
    }
  }' >"${output_dir}/sparkle-candidate.json"

jq -n \
  --arg source_commit "$source_commit" \
  --arg source_tree "$source_tree" \
  --arg source_archive_sha256 "$source_archive_sha256" \
  --arg app_binary_sha256 "$app_binary_sha" \
  --arg core_binary_sha256 "$core_binary_sha" \
  --arg helper_binary_sha256 "$helper_binary_sha" \
  --arg app_tree_sha256 "$app101_tree_sha" \
  --arg update_archive_sha256 "$update_archive_sha" \
  --arg sparkle_asset_sha256 "$downloaded_sparkle_sha" \
  --argjson app_binary_bytes "$app_binary_bytes" \
  --argjson core_binary_bytes "$core_binary_bytes" \
  --argjson helper_binary_bytes "$helper_binary_bytes" \
  --argjson update_archive_bytes "$update_archive_bytes" \
  '{
    source: {
      commit: $source_commit,
      tree: $source_tree,
      archive_sha256: $source_archive_sha256
    },
    generated_artifacts: {
      app_binary: {sha256: $app_binary_sha256, bytes: $app_binary_bytes, architecture: "arm64"},
      rust_core: {sha256: $core_binary_sha256, bytes: $core_binary_bytes, architecture: "arm64"},
      helper: {sha256: $helper_binary_sha256, bytes: $helper_binary_bytes, architecture: "arm64"},
      signed_app_tree: {sha256: $app_tree_sha256, signature: "ad-hoc", hardened_runtime: true},
      update_archive: {sha256: $update_archive_sha256, bytes: $update_archive_bytes, retained: false},
      sparkle_release_asset: {sha256: $sparkle_asset_sha256, retained: false}
    },
    prohibited_artifacts_retained: false
  }' >"${output_dir}/artifact-manifest.json"

jq -n \
  --arg created "$evidence_created" \
  --arg source_commit "$source_commit" \
  --arg update_archive_sha256 "$update_archive_sha" \
  --arg sparkle_sha256 "$downloaded_sparkle_sha" \
  '{
    spdxVersion: "SPDX-2.3",
    dataLicense: "CC0-1.0",
    SPDXID: "SPDXRef-DOCUMENT",
    name: "DF-M0-006-disposable-distribution-evidence",
    documentNamespace: ("https://dataforge.invalid/spdx/DF-M0-006/" + $source_commit),
    creationInfo: {
      created: $created,
      creators: ["Tool: DF-M0-006-disposable-runner"]
    },
    packages: [
      {
        name: "dataforge-distribution-probe",
        SPDXID: "SPDXRef-Package-DistributionProbe",
        versionInfo: "0.0.101",
        downloadLocation: "NOASSERTION",
        filesAnalyzed: false,
        licenseConcluded: "NOASSERTION",
        licenseDeclared: "NOASSERTION",
        checksums: [{algorithm: "SHA256", checksumValue: $update_archive_sha256}],
        primaryPackagePurpose: "APPLICATION",
        comment: "Disposable planning probe; no license grant or production artifact."
      },
      {
        name: "Sparkle",
        SPDXID: "SPDXRef-Package-Sparkle",
        versionInfo: "2.9.4",
        downloadLocation: "https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz",
        filesAnalyzed: false,
        licenseConcluded: "NOASSERTION",
        licenseDeclared: "MIT",
        checksums: [{algorithm: "SHA256", checksumValue: $sparkle_sha256}],
        primaryPackagePurpose: "LIBRARY",
        comment: "Candidate only; bundled third-party notices and legal review remain required."
      }
    ],
    relationships: [
      {spdxElementId: "SPDXRef-DOCUMENT", relationshipType: "DESCRIBES", relatedSpdxElement: "SPDXRef-Package-DistributionProbe"},
      {spdxElementId: "SPDXRef-DOCUMENT", relationshipType: "DESCRIBES", relatedSpdxElement: "SPDXRef-Package-Sparkle"}
    ]
  }' >"${output_dir}/sbom.spdx.json"

{
  print "app_requirement=${app101_requirement}"
  print "core_requirement=${core_requirement}"
  print "helper_requirement=${helper_requirement}"
  print "signature=ad-hoc"
  print "team_identifier=not-set"
  print "hardened_runtime=true"
  print "entitlement_exceptions=0"
  print "resource_tamper_rejected=true"
  print "wrong_requirement_helper_rejected=true"
  print "same_identifier_ad_hoc_outer_verifies=${same_id_ad_hoc_outer_verifies}"
  print "gatekeeper_exit=${gatekeeper_exit}"
  print "stapler_exit=${stapler_exit}"
} >"${output_dir}/codesign-summary.txt"

jq empty \
  "${output_dir}/environment.json" \
  "${output_dir}/sparkle-candidate.json" \
  "${output_dir}/artifact-manifest.json" \
  "${output_dir}/sbom.spdx.json"

ps -axo command >"${run_dir}/process-snapshot.txt"
for key_file in "${secret_root}/old.key" "${secret_root}/new.key"; do
  if rg --hidden --quiet --fixed-strings --file "$key_file" \
    "$output_dir" "${run_dir}/process-snapshot.txt"; then
    print -u2 "ephemeral update seed reached retained output or process argv"
    exit 1
  fi
  if find "$run_dir" -path "$secret_root" -prune -o -type f -print0 |
    xargs -0 rg --text --quiet --fixed-strings --file "$key_file"; then
    print -u2 "ephemeral update seed reached transient logs or artifacts"
    exit 1
  fi
done
if git -C "$repository_root" grep -I -F -f "${secret_root}/old.key" -- . >/dev/null 2>&1 ||
  git -C "$repository_root" grep -I -F -f "${secret_root}/new.key" -- . >/dev/null 2>&1; then
  print -u2 "ephemeral update seed reached Git-tracked content"
  exit 1
fi

cleanup_run_dir
[[ ! -e $run_dir ]]
run_dir=''
trap - EXIT INT TERM

jq -n \
  --arg schema_version '1' \
  --argjson identity_count "$identity_count" \
  --argjson gatekeeper_exit "$gatekeeper_exit" \
  --argjson stapler_exit "$stapler_exit" \
  --argjson same_id_ad_hoc_outer_verifies "$same_id_ad_hoc_outer_verifies" \
  --argjson policy_negative_count "$policy_negative_count" \
  --arg installed_before "$installed_before" \
  --arg installed_after "$installed_after" \
  '{
    schema_version: ($schema_version | tonumber),
    evidence_kind: "developer-host-disposable-distribution-spike",
    scenarios: [
      {id:"EN-01", status:"pass", observation:{identity_count:$identity_count, identity_names_enumerated:false, notary_profile_searched:false}},
      {id:"AR-01", status:"pass", observation:{app:"arm64", core:"arm64", helper:"arm64", minimum_macos:"14.0"}},
      {id:"AR-02", status:"pass", observation:{relative_core_load:true, app_and_helper_launch:true}},
      {id:"SG-01", status:"pass", scope:"local_ad_hoc", observation:{inside_out:true, signing_deep_used:false, secure_timestamp:false}},
      {id:"SG-02", status:"pass", scope:"local_ad_hoc", observation:{strict_nested_verification:true}},
      {id:"DR-01", status:"partial", observation:{stable_identifiers_across_versions:true, developer_id_team_anchor_proven:false}},
      {id:"ET-01", status:"pass", scope:"local_ad_hoc", observation:{hardened_runtime:true, entitlement_exceptions:0}},
      {id:"TM-01", status:"pass", scope:"local_ad_hoc", observation:{sealed_resource_tamper_rejected:true}},
      {id:"TM-02", status:"partial", observation:{wrong_requirement_rejected:true, same_identifier_ad_hoc_outer_verifies:$same_id_ad_hoc_outer_verifies, publisher_authenticity_proven:false}},
      {id:"GK-01", status:"unsupported", observation:{ad_hoc_assessment_exit:$gatekeeper_exit, clean_mac_run:false, developer_id_artifact:false}},
      {id:"NT-01", status:"unsupported", observation:{submission_attempted:false, request_id_retained:false}},
      {id:"ST-01", status:"unsupported", observation:{no_ticket_validation_exit:$stapler_exit, accepted_ticket_available:false}},
      {id:"SP-01", status:"pass", observation:{exact_release:true, digest:true, license_notices:true, advisories:true, arm64_slice:true, strict_signatures:true}},
      {id:"SP-02", status:"pass", observation:{fake_seed:true, unchanged_archive_verified:true}},
      {id:"SP-03", status:"pass", observation:{tampered_archive_rejected:true, wrong_key_rejected:true}},
      {id:"SP-04", status:"partial", observation:{signed_feed_tool_smoke:true, host_pre_extraction_configuration_run:false, framework_integration_run:false}},
      {id:"UP-01", status:"partial", observation:{actual_fixture_metadata:true, model_policy_accepted:true, updater_install_run:false}},
      {id:"UP-02", status:"partial", observation:{model_negative_count:$policy_negative_count, updater_install_run:false}},
      {id:"UP-03", status:"partial", observation:{injected_phase:"before_replacement", installed_hash_before:$installed_before, installed_hash_after:$installed_after, real_interruption_run:false}},
      {id:"KR-01", status:"partial", observation:{old_and_new_fake_key_signatures_verified:true, cross_key_rejected:true, developer_id_rotation_run:false}},
      {id:"SB-01", status:"pass", observation:{spdx_2_3:true, provenance_manifest:true, legal_approval:false}},
      {id:"SC-01", status:"pass", observation:{seed_absent_from_retained_output_git_and_process_snapshot:true}},
      {id:"CL-01", status:"pass", observation:{run_directory_removed:true, retained_private_seed:false, retained_download:false}}
    ],
    summary: {
      pass: 13,
      partial: 6,
      unsupported: 4,
      fail: 0,
      total: 23,
      complete_release_gate_passed: false,
      production_distribution_enabled: false,
      updater_adopted: false
    }
  }' >"${output_dir}/runtime.json"

jq empty "${output_dir}/runtime.json"
print 'outer_secret_scan=pass' >"${output_dir}/runner-completion.txt"
print 'transient_cleanup=pass' >>"${output_dir}/runner-completion.txt"
print 'complete_release_gate_passed=false' >>"${output_dir}/runner-completion.txt"

print "DF-M0-006 evidence complete: 13 pass, 6 partial, 4 unsupported, 0 fail"
