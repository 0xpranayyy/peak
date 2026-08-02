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
#   1. IDENTITY env (build phase may export EXPANDED_CODE_SIGN_IDENTITY)
#   2. EXPANDED_CODE_SIGN_IDENTITY / CODE_SIGN_IDENTITY /
#      CODE_SIGN_IDENTITY_FOR_DRIVERKIT from the Xcode build env (if set, not "-")
#   3. security find-identity: Apple Distribution → Apple Development →
#      iPhone Distribution → any codesigning identity
#   4. On CI (CI_XCODE_CLOUD / CI): brief wait/retry for keychain identities
#   5. On CI: create an ephemeral self-signed codesigning cert dedicated to
#      signing this XCFramework (Build actions often have no Apple certs)
#   Prefer a real Apple identity when present. Ephemeral self-signed is only
#   for Cloud Build / empty-keychain cases; Archive should use Distribution.

set -euo pipefail

EPHEMERAL_CERT_NAME="Peak PrivySDK CI Signer"

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

  # Xcode Cloud / CI: common DerivedData under CI_DERIVED_DATA_PATH
  if [ -n "${CI_DERIVED_DATA_PATH:-}" ]; then
    sp="${CI_DERIVED_DATA_PATH}/SourcePackages/checkouts/privy-ios/PrivySDK.xcframework"
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

  # Last resort: search under SRCROOT DerivedData-style checkouts
  if [ -n "${SRCROOT:-}" ]; then
    _hit="$(find "${SRCROOT}" -type d -path '*/SourcePackages/checkouts/privy-ios/PrivySDK.xcframework' 2>/dev/null | head -1 || true)"
    if [ -n "${_hit}" ] && [ -d "${_hit}" ]; then
      printf '%s\n' "${_hit}"
      return 0
    fi
  fi

  return 1
}

# True when running under Xcode Cloud or generic CI.
is_ci() {
  [ "${CI_XCODE_CLOUD:-}" = "TRUE" ] || [ "${CI_XCODE_CLOUD:-}" = "true" ] \
    || [ "${CI:-}" = "TRUE" ] || [ "${CI:-}" = "true" ] || [ "${CI:-}" = "1" ]
}

login_keychain() {
  if [ -f "${HOME}/Library/Keychains/login.keychain-db" ]; then
    printf '%s\n' "${HOME}/Library/Keychains/login.keychain-db"
  elif [ -f "${HOME}/Library/Keychains/login.keychain" ]; then
    printf '%s\n' "${HOME}/Library/Keychains/login.keychain"
  else
    security default-keychain -d user 2>/dev/null | sed -E 's/^[[:space:]]*"([^"]+)".*/\1/' || true
  fi
}

# Best-effort unlock so find-identity / codesign can see Cloud-managed certs.
unlock_keychain_if_needed() {
  _kc="$(login_keychain || true)"
  if [ -z "${_kc}" ]; then
    return 0
  fi
  # Xcode Cloud login keychain is often unlocked already; empty password is the
  # common CI default. Never print passwords.
  security unlock-keychain -p "" "${_kc}" >/dev/null 2>&1 \
    || security unlock-keychain "${_kc}" >/dev/null 2>&1 \
    || true
  security set-keychain-settings -t 3600 -u "${_kc}" >/dev/null 2>&1 || true
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
    # Prefer a non-ephemeral identity if both exist.
    _line="$(printf '%s\n' "${_list}" | grep -E '^[ ]*[0-9]+\)' | grep -v "${EPHEMERAL_CERT_NAME}" | head -1 || true)"
  fi
  if [ -z "${_line}" ]; then
    _line="$(printf '%s\n' "${_list}" | grep -E '^[ ]*[0-9]+\)' | head -1 || true)"
  fi
  if [ -z "${_line}" ]; then
    return 1
  fi
  identity_from_line "${_line}"
}

# True if a candidate string resolves to a usable codesigning identity.
identity_usable() {
  _cand="$1"
  [ -n "${_cand}" ] || return 1
  [ "${_cand}" != "-" ] || return 1
  [ "${_cand}" != "Don't Code Sign" ] || return 1
  # Generic preference strings without a matching cert are not usable.
  case "${_cand}" in
    "Apple Development"|"Apple Distribution"|"iPhone Developer"|"iPhone Distribution"|"Mac Developer"|"Mac App Distribution"|"Developer ID Application")
      security find-identity -v -p codesigning 2>/dev/null | grep -F "${_cand}" >/dev/null 2>&1
      return $?
      ;;
  esac
  # Hash (40 hex) or full "Apple Development: Name (TEAM)" — try codesign dry probe via find-identity.
  if printf '%s\n' "${_cand}" | grep -Eq '^[A-Fa-f0-9]{40}$'; then
    security find-identity -v -p codesigning 2>/dev/null | grep -qi "${_cand}" >/dev/null 2>&1
    return $?
  fi
  # Named identity — accept if find-identity lists it, else still try (local may work).
  if security find-identity -v -p codesigning 2>/dev/null | grep -F "${_cand}" >/dev/null 2>&1; then
    return 0
  fi
  # On non-CI, allow Xcode-expanded names that may still codesign.
  if ! is_ci; then
    return 0
  fi
  return 1
}

# Xcode build settings first (Cloud Archive often expands these).
identity_from_build_env() {
  for _var in IDENTITY EXPANDED_CODE_SIGN_IDENTITY CODE_SIGN_IDENTITY CODE_SIGN_IDENTITY_FOR_DRIVERKIT; do
    eval "_val=\${${_var}:-}"
    if identity_usable "${_val}"; then
      printf '%s\n' "${_val}"
      return 0
    fi
  done
  return 1
}

# Create a dedicated self-signed codesigning identity for XCFramework signing
# when Cloud Build has no Apple certs in the keychain. Satisfies TMS-91065
# (signature present); Archive still prefers Apple Distribution when available.
ensure_ephemeral_codesign_identity() {
  if ! is_ci; then
    return 1
  fi

  _kc="$(login_keychain || true)"
  if [ -z "${_kc}" ]; then
    echo "warning: no login keychain found; cannot create ephemeral signer" >&2
    return 1
  fi

  unlock_keychain_if_needed

  if security find-identity -v -p codesigning 2>/dev/null | grep -F "${EPHEMERAL_CERT_NAME}" >/dev/null 2>&1; then
    echo "identity_path=ephemeral_reuse name=${EPHEMERAL_CERT_NAME}" >&2
    printf '%s\n' "${EPHEMERAL_CERT_NAME}"
    return 0
  fi

  echo "warning: no Apple codesigning identity; creating ephemeral self-signed cert for PrivySDK XCFramework…" >&2
  _tmpdir="$(mktemp -d)"

  if ! openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "${_tmpdir}/key.pem" \
      -out "${_tmpdir}/cert.pem" \
      -days 2 \
      -subj "/CN=${EPHEMERAL_CERT_NAME}/O=Peak CI/OU=Xcode Cloud" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=codeSigning" \
      2>/dev/null; then
    echo "error: openssl failed to create ephemeral codesigning cert" >&2
    rm -rf "${_tmpdir}"
    return 1
  fi

  _p12_pw="$(openssl rand -hex 16)"
  # OpenSSL 3 defaults break macOS security import — use legacy PKCS#12.
  if ! openssl pkcs12 -export -legacy \
      -macalg sha1 \
      -keypbe PBE-SHA1-3DES \
      -certpbe PBE-SHA1-3DES \
      -inkey "${_tmpdir}/key.pem" \
      -in "${_tmpdir}/cert.pem" \
      -name "${EPHEMERAL_CERT_NAME}" \
      -out "${_tmpdir}/cert.p12" \
      -passout "pass:${_p12_pw}" 2>/dev/null; then
    if ! openssl pkcs12 -export \
        -inkey "${_tmpdir}/key.pem" \
        -in "${_tmpdir}/cert.pem" \
        -name "${EPHEMERAL_CERT_NAME}" \
        -out "${_tmpdir}/cert.p12" \
        -passout "pass:${_p12_pw}" 2>/dev/null; then
      echo "error: openssl pkcs12 export failed" >&2
      rm -rf "${_tmpdir}"
      return 1
    fi
  fi

  if ! security import "${_tmpdir}/cert.p12" \
      -k "${_kc}" \
      -P "${_p12_pw}" \
      -A \
      -T /usr/bin/codesign \
      -T /usr/bin/security >/dev/null 2>&1; then
    echo "error: security import of ephemeral cert failed" >&2
    rm -rf "${_tmpdir}"
    return 1
  fi

  # Allow codesign without UI prompt (empty login password is typical on Cloud).
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "${_kc}" >/dev/null 2>&1 || true
  security add-trusted-cert -p codeSign -k "${_kc}" "${_tmpdir}/cert.pem" >/dev/null 2>&1 || true

  rm -rf "${_tmpdir}"

  if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "${EPHEMERAL_CERT_NAME}" >/dev/null 2>&1; then
    echo "error: ephemeral cert imported but not visible to find-identity" >&2
    security find-identity -v -p codesigning 2>&1 | sed 's/^/  /' >&2 || true
    return 1
  fi

  echo "identity_path=ephemeral_created name=${EPHEMERAL_CERT_NAME}" >&2
  printf '%s\n' "${EPHEMERAL_CERT_NAME}"
  return 0
}

resolve_identity() {
  unlock_keychain_if_needed

  _id=""
  _id="$(identity_from_build_env || true)"
  if [ -n "${_id}" ]; then
    echo "identity_path=build_env value=${_id}" >&2
    printf '%s\n' "${_id}"
    return 0
  fi

  _id="$(identity_from_keychain || true)"
  if [ -n "${_id}" ]; then
    echo "identity_path=keychain value=${_id}" >&2
    printf '%s\n' "${_id}"
    return 0
  fi

  # On Xcode Cloud / CI, signing certs may land in the keychain slightly after
  # the "Sign PrivySDK" phase starts — retry briefly (skip long wait during
  # PREPARE_IDENTITY_ONLY; Archive certs often appear only inside xcodebuild).
  if is_ci; then
    if [ "${PREPARE_IDENTITY_ONLY:-}" != "1" ]; then
      echo "warning: no codesigning identity yet; waiting for Cloud keychain (up to ~30s)…" >&2
      _attempt=0
      while [ "${_attempt}" -lt 6 ]; do
        sleep 5
        _attempt=$((_attempt + 1))
        unlock_keychain_if_needed
        _id="$(identity_from_build_env || true)"
        if [ -z "${_id}" ]; then
          _id="$(identity_from_keychain || true)"
        fi
        if [ -n "${_id}" ]; then
          echo "identity_path=keychain_retry attempt=${_attempt} value=${_id}" >&2
          printf '%s\n' "${_id}"
          return 0
        fi
        echo "  retry ${_attempt}/6: still no identity" >&2
      done
    fi

    # Build - iOS often never installs Distribution/Development certs.
    # Fall back to an ephemeral self-signed identity so the phase succeeds
    # and PrivySDK.xcframework still gets a _CodeSignature (TMS-91065).
    _id="$(ensure_ephemeral_codesign_identity || true)"
    if [ -n "${_id}" ]; then
      printf '%s\n' "${_id}"
      return 0
    fi
  fi

  return 1
}

# Optional: CI pre-xcodebuild only needs a usable identity in the keychain.
if [ "${PREPARE_IDENTITY_ONLY:-}" = "1" ]; then
  _prep="$(resolve_identity || true)"
  if [ -z "${_prep}" ]; then
    echo "error: PREPARE_IDENTITY_ONLY failed — no codesigning identity" >&2
    exit 1
  fi
  echo "Prepared codesigning identity for PrivySDK: ${_prep}"
  exit 0
fi

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
  echo "error: EXPANDED_CODE_SIGN_IDENTITY='${EXPANDED_CODE_SIGN_IDENTITY:-}' CODE_SIGN_IDENTITY='${CODE_SIGN_IDENTITY:-}' IDENTITY='${IDENTITY:-}'" >&2
  echo "error: CI_XCODE_CLOUD='${CI_XCODE_CLOUD:-}' CI='${CI:-}' CI_XCODEBUILD_ACTION='${CI_XCODEBUILD_ACTION:-}'" >&2
  if is_ci; then
    echo "error: On Xcode Cloud, prefer workflow action Archive - iOS (Distribution identity)." >&2
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
