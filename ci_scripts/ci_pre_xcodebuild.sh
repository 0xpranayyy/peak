#!/bin/sh
# Xcode Cloud: before xcodebuild, unlock the keychain and best-effort prepare a
# codesigning identity for the Sign PrivySDK build phase.
#
# This hook must NEVER fail the Cloud build:
#   - SPM has not resolved yet, so PrivySDK.xcframework is usually absent.
#   - Ephemeral cert creation can fail on some runners.
# Actual signing happens in the Xcode "Sign PrivySDK" build phase after packages
# resolve. Prefer workflow action Archive - iOS (Distribution certs).
#
# See docs/XCODE_CLOUD.md.
set -u

ROOT="${CI_PRIMARY_REPOSITORY_PATH:-.}"
SCRIPT="${ROOT}/scripts/sign-privy-xcframework.sh"
ACTION="${CI_XCODEBUILD_ACTION:-unknown}"

echo "ci_pre_xcodebuild: action=${ACTION}"
echo "ci_pre_xcodebuild: prep only — identity/keychain; signing stays in the build phase after SPM resolve"

if [ ! -f "${SCRIPT}" ]; then
  echo "ci_pre_xcodebuild: ${SCRIPT} missing — skipping (build phase will handle signing)"
  exit 0
fi

# Export so the script treats this as Cloud even if the runner omits flags.
export CI_XCODE_CLOUD="${CI_XCODE_CLOUD:-TRUE}"
export PREPARE_IDENTITY_ONLY=1

echo "ci_pre_xcodebuild: preparing codesigning identity (best-effort)…"
if /bin/sh "${SCRIPT}"; then
  echo "ci_pre_xcodebuild: identity prep succeeded"
else
  _rc=$?
  echo "ci_pre_xcodebuild: warning: identity prep exited ${_rc} — continuing; build phase signs after SPM resolve" >&2
fi

# Do not attempt to sign PrivySDK.xcframework here. Packages are typically not
# resolved until xcodebuild runs; a missing path must not fail this hook.

echo "ci_pre_xcodebuild: done (exit 0)"
exit 0
