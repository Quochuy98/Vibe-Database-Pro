#!/bin/zsh

set -euo pipefail

if [[ $# -ne 8 ]]; then
  print -u2 "usage: check-update-policy.sh CURRENT_BUILD CANDIDATE_BUILD CURRENT_BUNDLE CANDIDATE_BUNDLE EXPECTED_CHANNEL CANDIDATE_CHANNEL EXPECTED_ARCH CANDIDATE_ARCH"
  exit 64
fi

readonly current_build=$1
readonly candidate_build=$2
readonly current_bundle=$3
readonly candidate_bundle=$4
readonly expected_channel=$5
readonly candidate_channel=$6
readonly expected_arch=$7
readonly candidate_arch=$8

reject() {
  print -u2 "policy-reject=$1"
  exit 65
}

[[ $current_build =~ '^[0-9]+$' ]] || reject invalid-current-build
[[ $candidate_build =~ '^[0-9]+$' ]] || reject invalid-candidate-build
(( candidate_build > current_build )) || reject non-monotonic-build
[[ $candidate_bundle == $current_bundle ]] || reject wrong-bundle
[[ $candidate_channel == $expected_channel ]] || reject wrong-channel
[[ $candidate_arch == $expected_arch ]] || reject wrong-architecture

print "policy=accepted build=${candidate_build} channel=${candidate_channel} arch=${candidate_arch}"
