#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "usage: sign-local.sh APP_PATH"
  exit 64
fi

readonly app_path=$1
readonly core_path="${app_path}/Contents/Frameworks/libdataforge_distribution_core.dylib"
readonly helper_path="${app_path}/Contents/Helpers/DataForgeDistributionHelper"
readonly executable_path="${app_path}/Contents/MacOS/DataForgeDistributionProbe"

for item in "$app_path" "$core_path" "$helper_path" "$executable_path"; do
  if [[ ! -e $item ]]; then
    print -u2 "missing signing input: $item"
    exit 66
  fi
done

sign_item() {
  local identifier=$1
  local item_path=$2
  codesign \
    --force \
    --sign - \
    --timestamp=none \
    --options runtime \
    --identifier "$identifier" \
    --requirements "=designated => identifier \"${identifier}\"" \
    "$item_path"
}

sign_item com.dataforge.distribution-probe.core "$core_path"
sign_item com.dataforge.distribution-probe.helper "$helper_path"
sign_item com.dataforge.distribution-probe "$app_path"
