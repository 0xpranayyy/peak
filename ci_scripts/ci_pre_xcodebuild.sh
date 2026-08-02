#!/bin/sh
# Xcode Cloud: before xcodebuild, unlock the keychain and ensure a codesigning
# identity exists for the Sign PrivySDK build phase.
#
# Build - iOS workflows often have an empty keychain (no Distribution cert).
# Preparing an ephemeral self-signed identity here avoids a hard fail later.
# Archive - iOS should still pick Apple Distribution when Cloud installs it.
#
# See docs/XCODE_CLOUD.md.
set -eu

ROOT="${CI_PRIMARY_REPOSITORY_PATH:-.}"
SCRIPT="${ROOT}/scripts/sign-privy-xcframework.sh"

if [ ! -f "${SCRIPT}" ]; then
  echo "ci_pre_xcodebuild: ${SCRIPT} missing — skipping Privy identity prep"
  exit 0
fi

echo "ci_pre_xcodebuild: action=${CI_XCODEBUILD_ACTION:-unknown} preparing PrivySDK codesign identity…"
# Export so the script treats this as Cloud even if the runner omits flags.
export CI_XCODE_CLOUD="${CI_XCODE_CLOUD:-TRUE}"
export PREPARE_IDENTITY_ONLY=1

/bin/sh "${SCRIPT}"

# If SPM already resolved (warm DerivedData), sign early as a belt-and-suspenders.
unset PREPARE_IDENTITY_ONLY
if [ -n "${CI_DERIVED_DATA_PATH:-}" ]; then
  XCF="${CI_DERIVED_DATA_PATH}/SourcePackages/checkouts/privy-ios/PrivySDK.xcframework"
  if [ -d "${XCF}" ]; then
    echo "ci_pre_xcodebuild: signing existing checkout at ${XCF}"
    /bin/sh "${SCRIPT}" "${XCF}" || {
      echo "warning: early PrivySDK sign failed; build phase will retry" >&2
    }
  fi
fi

echo "ci_pre_xcodebuild: done"
