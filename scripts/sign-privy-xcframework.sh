#!/bin/sh
# Sign PrivySDK.xcframework so App Store Connect accepts the SwiftyJSON
# fingerprint inside the binary (TMS-91065).
#
# Privy 2.14.0 (latest as of 2026-08-01) ships an unsigned XCFramework.
# Apple requires a signature for listed third-party SDKs when used as
# binary dependencies, including SDKs that *repackage* them (SwiftyJSON
# is linked into PrivySDK). Sentry's XCFramework has a top-level
# _CodeSignature; Privy's does not.
#
# Prefer a future privy-ios release that ships vendor-signed binaries +
# PrivacyInfo.xcprivacy; this script is a local workaround.
#
# Usage:
#   ./scripts/sign-privy-xcframework.sh [path-to-PrivySDK.xcframework]
#   (Xcode build phase sets SRCROOT / DERIVED_DATA paths automatically)
#
# Identity selection (Xcode Cloud–aware):
#   1. EXPANDED_CODE_SIGN_IDENTITY / CODE_SIGN_IDENTITY /
#      CODE_SIGN_IDENTITY_FOR_DRIVERKIT from the Xcode build env (if set, not "-")
#   2. security find-identity: Apple Distribution → Apple Development →
#      iPhone Distribution → any codesigning identity
#   3. On CI (CI_XCODE_CLOUD / CI): brief wait/retry for keychain identities
#   Prefer a real Apple identity. Do not use ad-hoc (`codesign -s -`) for
#   App Store / TestFlight nested XCFrameworks.

set -euo pipefail

find_xcframework() {
  if [ -n "${1:-}" ] && [ -d "$1" ]; then
    printf '%s\n' "$1"
    return 0
  fi

  # DerivedData SourcePackages (normal Xcode / xcodebuild)
  if [ -n "${BUILD_DIR:-}" ]; then
    sp="${BUILD_DIR%/Build/*}/SourcePackages/checkouts/privy-ios/PrivySDK.xcframework"
    if [ -d "$sp" ]; then
      printf '%s\n' "$sp"
      return 0
    fi
  fi

  # Explicit DerivedData env (some CI setups)
  if [ -n "${PROJECT_TEMP_DIR:-}" ]; then
    root="${PROJECT_TEMP_DIR%/Build/*}"
    sp="$root/SourcePackages/checkouts/privy-ios/PrivySDK.xcframework"
    if [ -d "$sp" ]; then
      printf '%s\n' "$sp"
      return 0
    fi
  fi

  # Local SPM cache used by Peak tooling
  if [ -n "${SRCROOT:-}" ] && [ -d "$SRCROOT/.spm-cache/checkouts/privy-ios/PrivySDK.xcframework" ]; then
    printf '%s\n' "$SRCROOT/.spm-cache/checkouts/privy-ios/PrivySDK.xcframework"
    return 0
  fi

  return 1
}

# True when running under Xcode Cloud or generic CI.
is_ci() {
  [ "${CI_XCODE_CLOUD:-}" = "TRUE" ] || [ "${CI_XCODE_CLOUD:-}" = "true" ] \
    || [ "${CI:-}" = "TRUE" ] || [ "${CI:-}" = "true" ] || [ "${CI:-}" = "1" ]
}

# Extract the quoted identity name from a `security find-identity` line.
identity_from_line() {
  printf '%s\n' "$1" | sed -E 's/.*"([^"]+)".*/\1/'
}

# Prefer named Apple identities, then any codesigning identity present.
identity_from_keychain() {
  _list="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if [ -z "${_list}" ]; then
    return 1
  fi

  _line="$(printf '%s\n' "${_list}" | grep -E 'Apple Distribution' | head -1 || true)"
  if [ -z "${_line}" ]; then
    _line="$(printf '%s\n' "${_list}" | grep -E 'Apple Development' | head -1 || true)"
  fi
  if [ -z "${_line}" ]; then
    _line="$(printf '%s\n' "${_list}" | grep -E 'iPhone Distribution' | head -1 || true)"
  fi
  if [ -z "${_line}" ]; then
    # Any valid identity line: "  1) HASH "Name""
    _line="$(printf '%s\n' "${_list}" | grep -E '^[ ]*[0-9]+\)' | head -1 || true)"
  fi
  if [ -z "${_line}" ]; then
    return 1
  fi
  identity_from_line "${_line}"
}

# Xcode build settings first (Cloud often has these before find-identity is ready).
identity_from_build_env() {
  for _var in EXPANDED_CODE_SIGN_IDENTITY CODE_SIGN_IDENTITY CODE_SIGN_IDENTITY_FOR_DRIVERKIT; do
    eval "_val=\${${_var}:-}"
    if [ -n "${_val}" ] && [ "${_val}" != "-" ] && [ "${_val}" != "Don't Code Sign" ]; then
      printf '%s\n' "${_val}"
      return 0
    fi
  done
  return 1
}

resolve_identity() {
  _id=""
  _id="$(identity_from_build_env || true)"
  if [ -n "${_id}" ]; then
    printf '%s\n' "${_id}"
    return 0
  fi

  _id="$(identity_from_keychain || true)"
  if [ -n "${_id}" ]; then
    printf '%s\n' "${_id}"
    return 0
  fi

  # On Xcode Cloud / CI, signing certs may land in the keychain slightly after
  # the early "Sign PrivySDK" phase starts — retry briefly.
  if is_ci; then
    echo "warning: no codesigning identity yet; waiting for Cloud keychain (up to ~30s)…"
    _attempt=0
    while [ "${_attempt}" -lt 6 ]; do
      sleep 5
      _attempt=$((_attempt + 1))
      _id="$(identity_from_build_env || true)"
      if [ -z "${_id}" ]; then
        _id="$(identity_from_keychain || true)"
      fi
      if [ -n "${_id}" ]; then
        echo "Found codesigning identity after retry ${_attempt}"
        printf '%s\n' "${_id}"
        return 0
      fi
      echo "  retry ${_attempt}/6: still no identity"
    done
  fi

  return 1
}

XCF="$(find_xcframework "${1:-}" || true)"
if [ -z "${XCF}" ]; then
  echo "warning: PrivySDK.xcframework not found; skipping TMS-91065 sign workaround"
  exit 0
fi

# SPM checkouts often mark slice files read-only; codesign needs write.
chmod -R u+w "${XCF}" 2>/dev/null || true

# Inject minimal privacy manifest into device/sim slices if missing.
# Apple also requires PrivacyInfo for listed SDKs (SwiftyJSON) on new apps.
PRIVACY_TMP="$(mktemp)"
cat >"${PRIVACY_TMP}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array/>
</dict>
</plist>
PLIST

find "${XCF}" -type d -name 'PrivySDK.framework' | while IFS= read -r fw; do
  dest="${fw}/PrivacyInfo.xcprivacy"
  # macOS-style versions layout
  if [ -d "${fw}/Versions/A" ]; then
    dest="${fw}/Versions/A/Resources/PrivacyInfo.xcprivacy"
    mkdir -p "${fw}/Versions/A/Resources"
  fi
  if [ ! -f "${dest}" ]; then
    cp "${PRIVACY_TMP}" "${dest}"
    echo "Added PrivacyInfo.xcprivacy → ${dest}"
  fi
done
rm -f "${PRIVACY_TMP}"

IDENTITY="$(resolve_identity || true)"
if [ -z "${IDENTITY}" ]; then
  echo "error: no codesigning identity available to sign PrivySDK.xcframework" >&2
  echo "error: dump of security find-identity -v -p codesigning:" >&2
  security find-identity -v -p codesigning 2>&1 | sed 's/^/  /' >&2 || true
  echo "error: EXPANDED_CODE_SIGN_IDENTITY='${EXPANDED_CODE_SIGN_IDENTITY:-}' CODE_SIGN_IDENTITY='${CODE_SIGN_IDENTITY:-}'" >&2
  if is_ci; then
    echo "error: On Xcode Cloud Archive, a Distribution cert should exist after signing setup." >&2
    echo "error: Confirm automatic signing for team 49BZ7S974W and re-run the workflow." >&2
  else
    echo "error: Locally: open Xcode → Settings → Accounts, download certificates," >&2
    echo "error: or set CODE_SIGN_IDENTITY / sign in with a Development team." >&2
  fi
  exit 1
fi

# Re-sign whenever missing or ad-hoc; always re-sign after PrivacyInfo inject
# so CodeResources stay consistent.
echo "Signing PrivySDK.xcframework with: ${IDENTITY}"
echo "Path: ${XCF}"
codesign --force --timestamp -v --sign "${IDENTITY}" "${XCF}"
codesign --verify --verbose=2 "${XCF}"
echo "PrivySDK.xcframework signature OK (TMS-91065 workaround)"
