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

# Prefer Apple Distribution (matches how Sentry ships); fall back to build identity.
IDENTITY=""
if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
  IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY}"
fi
DIST_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Distribution' | head -1 || true)"
if [ -n "${DIST_LINE}" ]; then
  IDENTITY="$(printf '%s\n' "${DIST_LINE}" | sed -E 's/.*"([^"]+)".*/\1/')"
fi
if [ -z "${IDENTITY}" ]; then
  DEV_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' | head -1 || true)"
  if [ -n "${DEV_LINE}" ]; then
    IDENTITY="$(printf '%s\n' "${DEV_LINE}" | sed -E 's/.*"([^"]+)".*/\1/')"
  fi
fi

if [ -z "${IDENTITY}" ]; then
  echo "error: no codesigning identity available to sign PrivySDK.xcframework"
  exit 1
fi

# Re-sign whenever missing or ad-hoc; always re-sign after PrivacyInfo inject
# so CodeResources stay consistent.
echo "Signing PrivySDK.xcframework with: ${IDENTITY}"
echo "Path: ${XCF}"
codesign --force --timestamp -v --sign "${IDENTITY}" "${XCF}"
codesign --verify --verbose=2 "${XCF}"
echo "PrivySDK.xcframework signature OK (TMS-91065 workaround)"
