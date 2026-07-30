#!/bin/zsh

set -euo pipefail

if [[ $# -lt 3 || $# -gt 5 ]]; then
  print -u2 "usage: build.sh OUTPUT_ROOT BUILD_VERSION CHANNEL [BUNDLE_ID] [ARCH]"
  exit 64
fi

readonly output_root=$1
readonly build_version=$2
readonly channel=$3
readonly bundle_id=${4:-com.dataforge.distribution-probe}
readonly architecture=${5:-arm64}
readonly script_dir=${0:A:h}
readonly spike_root=${script_dir:h}

if [[ $output_root != /* ]]; then
  print -u2 "OUTPUT_ROOT must be absolute"
  exit 64
fi
if [[ ! $build_version =~ '^[0-9]+$' ]]; then
  print -u2 "BUILD_VERSION must be an unsigned integer"
  exit 64
fi
if [[ $channel != stable && $channel != beta ]]; then
  print -u2 "CHANNEL must be stable or beta"
  exit 64
fi
if [[ ! $bundle_id =~ '^com\.dataforge\.[a-z0-9.-]+$' ]]; then
  print -u2 "BUNDLE_ID is outside the disposable DataForge namespace"
  exit 64
fi
if [[ $architecture != arm64 ]]; then
  print -u2 "only the frozen arm64 spike architecture may be built"
  exit 64
fi

readonly app_name="DataForgeDistributionProbe-${build_version}.app"
readonly app_path="${output_root}/${app_name}"
readonly contents="${app_path}/Contents"
readonly frameworks="${contents}/Frameworks"
readonly helpers="${contents}/Helpers"
readonly macos="${contents}/MacOS"
readonly resources="${contents}/Resources"
readonly cargo_target="${output_root}/cargo-target"

mkdir -p "$frameworks" "$helpers" "$macos" "$resources"

MACOSX_DEPLOYMENT_TARGET=14.0 \
  CARGO_TARGET_DIR="$cargo_target" \
  cargo build \
    --manifest-path "${spike_root}/Cargo.toml" \
    --locked \
    --release \
    --target aarch64-apple-darwin

cp \
  "${cargo_target}/aarch64-apple-darwin/release/libdataforge_distribution_core.dylib" \
  "${frameworks}/libdataforge_distribution_core.dylib"
/usr/bin/install_name_tool \
  -id @rpath/libdataforge_distribution_core.dylib \
  "${frameworks}/libdataforge_distribution_core.dylib"

swiftc \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target arm64-apple-macosx14.0 \
  "${spike_root}/Sources/Helper/main.swift" \
  -o "${helpers}/DataForgeDistributionHelper"

swiftc \
  -parse-as-library \
  -O \
  -warnings-as-errors \
  -target arm64-apple-macosx14.0 \
  "${spike_root}/Sources/App/main.swift" \
  -L "$frameworks" \
  -ldataforge_distribution_core \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks \
  -o "${macos}/DataForgeDistributionProbe"

plutil -create xml1 "${contents}/Info.plist"
plutil -insert CFBundleDevelopmentRegion -string en "${contents}/Info.plist"
plutil -insert CFBundleDisplayName -string DataForgeDistributionProbe "${contents}/Info.plist"
plutil -insert CFBundleExecutable -string DataForgeDistributionProbe "${contents}/Info.plist"
plutil -insert CFBundleIdentifier -string "$bundle_id" "${contents}/Info.plist"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "${contents}/Info.plist"
plutil -insert CFBundleName -string DataForgeDistributionProbe "${contents}/Info.plist"
plutil -insert CFBundlePackageType -string APPL "${contents}/Info.plist"
plutil -insert CFBundleShortVersionString -string "0.0.${build_version}" "${contents}/Info.plist"
plutil -insert CFBundleVersion -string "$build_version" "${contents}/Info.plist"
plutil -insert DataForgeUpdateChannel -string "$channel" "${contents}/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "${contents}/Info.plist"
plutil -insert LSUIElement -bool true "${contents}/Info.plist"

print -r -- "build=${build_version}" > "${resources}/probe-version.txt"
print -r -- "channel=${channel}" >> "${resources}/probe-version.txt"
print -r -- "bundle=${bundle_id}" >> "${resources}/probe-version.txt"

chmod 0755 \
  "${helpers}/DataForgeDistributionHelper" \
  "${macos}/DataForgeDistributionProbe"

print -r -- "$app_path"
