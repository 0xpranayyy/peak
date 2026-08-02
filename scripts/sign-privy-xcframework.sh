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
#      (skipped for Build-only when identities are already empty/-)
#   5. On CI: create an ephemeral self-signed codesigning cert in a
#      temporary keychain (Build actions often have no Apple certs)
#   Prefer a real Apple identity when present. Ephemeral self-signed is only
#   for Cloud Build / empty-keychain cases; Archive should use Distribution.
#
# Build-only policy: if ephemeral import still fails on a pure Build action
# (or empty/- CODE_SIGN identities), exit 0 with a loud skip message so the
# compile check can pass. Archive / install must still sign or fail clearly.

set -euo pipefail

EPHEMERAL_CERT_NAME="Peak PrivySDK CI Signer"
EPHEMERAL_KC_PATH=""
EPHEMERAL_KC_PASSWORD=""

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

# Xcode Cloud: CI_XCODEBUILD_ACTION is build | archive | test | analyze | …
ci_xcodebuild_action() {
  printf '%s\n' "${CI_XCODEBUILD_ACTION:-}" | tr '[:upper:]' '[:lower:]'
}

# Pure compile check — no Distribution identity expected.
is_build_only_action() {
  case "$(ci_xcodebuild_action)" in
    build) return 0 ;;
    *) return 1 ;;
  esac
}

# Archive / install must produce a signed XCFramework for TestFlight / TMS-91065.
is_signing_required_action() {
  case "$(ci_xcodebuild_action)" in
    archive|install) return 0 ;;
    *) return 1 ;;
  esac
}

# True when Xcode expanded identities are empty or ad-hoc placeholder "-".
build_env_identities_empty() {
  _exp="${EXPANDED_CODE_SIGN_IDENTITY:-}"
  _csi="${CODE_SIGN_IDENTITY:-}"
  _id="${IDENTITY:-}"
  _empty_or_dash() {
    [ -z "$1" ] || [ "$1" = "-" ]
  }
  _empty_or_dash "${_exp}" && _empty_or_dash "${_csi}" && _empty_or_dash "${_id}"
}

skip_sign_build_only() {
  echo "============================================================" >&2
  echo "Skipping PrivySDK sign on Build-only; add Archive - iOS for TestFlight/TMS-91065" >&2
  echo "============================================================" >&2
  echo "warning: CI_XCODEBUILD_ACTION='${CI_XCODEBUILD_ACTION:-}' EXPANDED_CODE_SIGN_IDENTITY='${EXPANDED_CODE_SIGN_IDENTITY:-}' CODE_SIGN_IDENTITY='${CODE_SIGN_IDENTITY:-}'" >&2
  echo "warning: Build - iOS does not install Apple Distribution certs. Edit the Xcode Cloud workflow → Actions → Archive - iOS." >&2
  exit 0
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

# Log security/openssl stderr without leaking passwords / PEM material.
log_sanitized_err() {
  _label="$1"
  _file="$2"
  if [ ! -s "${_file}" ]; then
    echo "  ${_label}: (no stderr)" >&2
    return 0
  fi
  # Drop lines that look like PEM bodies or pass= fragments.
  sed -E \
    -e '/^-----BEGIN /,/^-----END /d' \
    -e 's/pass:[^[:space:]]+/pass:***/g' \
    -e 's/-P[[:space:]]+[^[:space:]]+/-P ***/g' \
    -e 's/-k[[:space:]]+[^[:space:]]+/-k ***/g' \
    -e 's/-passout[[:space:]]+[^[:space:]]+/-passout ***/g' \
    -e 's/-passin[[:space:]]+[^[:space:]]+/-passin ***/g' \
    "${_file}" | sed 's/^/  /' >&2 || true
}

# Create + unlock a dedicated temporary keychain (known password → reliable
# set-key-partition-list). Prefer this over login.keychain on Xcode Cloud.
setup_ephemeral_keychain() {
  _base="${TMPDIR:-/tmp}"
  EPHEMERAL_KC_PATH="${_base}/peak-privy-ci-$$.keychain-db"
  EPHEMERAL_KC_PASSWORD="$(openssl rand -hex 24)"
  rm -f "${EPHEMERAL_KC_PATH}"

  if ! security create-keychain -p "${EPHEMERAL_KC_PASSWORD}" "${EPHEMERAL_KC_PATH}" >/dev/null 2>&1; then
    echo "error: security create-keychain failed for ephemeral signer" >&2
    EPHEMERAL_KC_PATH=""
    return 1
  fi
  security set-keychain-settings -lut 21600 "${EPHEMERAL_KC_PATH}" >/dev/null 2>&1 || true
  if ! security unlock-keychain -p "${EPHEMERAL_KC_PASSWORD}" "${EPHEMERAL_KC_PATH}" >/dev/null 2>&1; then
    echo "error: security unlock-keychain failed for ephemeral signer" >&2
    security delete-keychain "${EPHEMERAL_KC_PATH}" >/dev/null 2>&1 || true
    EPHEMERAL_KC_PATH=""
    return 1
  fi

  # Prepend ephemeral keychain to the user search list (keep existing).
  _existing="$(security list-keychains -d user 2>/dev/null | sed -E 's/^[[:space:]]*"([^"]+)".*/\1/' | tr '\n' ' ' || true)"
  # shellcheck disable=SC2086
  security list-keychains -d user -s "${EPHEMERAL_KC_PATH}" ${_existing} >/dev/null 2>&1 || true
  echo "ephemeral_keychain=created path_basename=$(basename "${EPHEMERAL_KC_PATH}")" >&2
  return 0
}

# Export PKCS#12 in a form macOS `security import` accepts (LibreSSL / OpenSSL 3).
export_ephemeral_p12() {
  _tmpdir="$1"
  _p12_pw="$2"
  _err="${_tmpdir}/pkcs12.err"

  # macOS ships LibreSSL (no -legacy). OpenSSL 3 may need -legacy for macOS import.
  if openssl pkcs12 -export \
      -inkey "${_tmpdir}/key.pem" \
      -in "${_tmpdir}/cert.pem" \
      -name "${EPHEMERAL_CERT_NAME}" \
      -out "${_tmpdir}/cert.p12" \
      -passout "pass:${_p12_pw}" 2>"${_err}"; then
    echo "ephemeral_p12=default" >&2
    return 0
  fi
  echo "warning: openssl pkcs12 default export failed; trying -legacy…" >&2
  log_sanitized_err "pkcs12_default" "${_err}"

  if openssl pkcs12 -export -legacy \
      -macalg sha1 \
      -keypbe PBE-SHA1-3DES \
      -certpbe PBE-SHA1-3DES \
      -inkey "${_tmpdir}/key.pem" \
      -in "${_tmpdir}/cert.pem" \
      -name "${EPHEMERAL_CERT_NAME}" \
      -out "${_tmpdir}/cert.p12" \
      -passout "pass:${_p12_pw}" 2>"${_err}"; then
    echo "ephemeral_p12=legacy" >&2
    return 0
  fi
  echo "error: openssl pkcs12 export failed" >&2
  log_sanitized_err "pkcs12_legacy" "${_err}"
  return 1
}

# Import PKCS#12 into the ephemeral keychain; fall back to PEM cert+key.
import_ephemeral_identity() {
  _tmpdir="$1"
  _p12_pw="$2"
  _kc="${EPHEMERAL_KC_PATH}"
  _err="${_tmpdir}/import.err"

  # Primary: PKCS#12 with codesign/security trusted for non-interactive use.
  if security import "${_tmpdir}/cert.p12" \
      -k "${_kc}" \
      -P "${_p12_pw}" \
      -A \
      -t cert \
      -f pkcs12 \
      -T /usr/bin/codesign \
      -T /usr/bin/security \
      >/dev/null 2>"${_err}"; then
    echo "ephemeral_import=pkcs12" >&2
  else
    echo "warning: security import pkcs12 failed; trying PEM cert+key…" >&2
    log_sanitized_err "import_pkcs12" "${_err}"

    if ! security import "${_tmpdir}/cert.pem" \
        -k "${_kc}" \
        -A \
        -t cert \
        -T /usr/bin/codesign \
        -T /usr/bin/security \
        >/dev/null 2>"${_err}"; then
      echo "error: security import of ephemeral cert.pem failed" >&2
      log_sanitized_err "import_cert_pem" "${_err}"
      return 1
    fi
    if ! security import "${_tmpdir}/key.pem" \
        -k "${_kc}" \
        -A \
        -t priv \
        -T /usr/bin/codesign \
        -T /usr/bin/security \
        >/dev/null 2>"${_err}"; then
      echo "error: security import of ephemeral key.pem failed" >&2
      log_sanitized_err "import_key_pem" "${_err}"
      return 1
    fi
    echo "ephemeral_import=pem" >&2
  fi

  # Allow codesign without UI prompt (requires known keychain password).
  if ! security set-key-partition-list \
      -S apple-tool:,apple:,codesign: \
      -s \
      -k "${EPHEMERAL_KC_PASSWORD}" \
      "${_kc}" >/dev/null 2>"${_err}"; then
    echo "warning: set-key-partition-list failed (codesign may prompt / fail)" >&2
    log_sanitized_err "partition_list" "${_err}"
  else
    echo "ephemeral_partition_list=ok" >&2
  fi

  # Trust for code signing is best-effort (may require root on some hosts).
  security add-trusted-cert -p codeSign -k "${_kc}" "${_tmpdir}/cert.pem" >/dev/null 2>&1 || true
  return 0
}

# True if the named identity can codesign (self-signed often missing from
# find-identity -p codesigning until trusted).
ephemeral_identity_can_sign() {
  _probe="$(mktemp)"
  printf 'peak-privy-ci-probe\n' >"${_probe}"
  if codesign --force --sign "${EPHEMERAL_CERT_NAME}" "${_probe}" >/dev/null 2>&1; then
    rm -f "${_probe}"
    return 0
  fi
  rm -f "${_probe}"
  return 1
}

# Create a dedicated self-signed codesigning identity for XCFramework signing
# when Cloud Build has no Apple certs in the keychain. Satisfies TMS-91065
# (signature present); Archive still prefers Apple Distribution when available.
ensure_ephemeral_codesign_identity() {
  if ! is_ci; then
    return 1
  fi

  unlock_keychain_if_needed

  # Reuse if cert is present and codesign accepts it (find-identity often
  # omits untrusted self-signed certs even when codesign works).
  if security find-certificate -a -c "${EPHEMERAL_CERT_NAME}" >/dev/null 2>&1 \
      || security find-identity -v -p codesigning 2>/dev/null | grep -F "${EPHEMERAL_CERT_NAME}" >/dev/null 2>&1; then
    if ephemeral_identity_can_sign; then
      echo "identity_path=ephemeral_reuse name=${EPHEMERAL_CERT_NAME}" >&2
      printf '%s\n' "${EPHEMERAL_CERT_NAME}"
      return 0
    fi
  fi

  echo "warning: no Apple codesigning identity; creating ephemeral self-signed cert for PrivySDK XCFramework…" >&2

  if ! setup_ephemeral_keychain; then
    return 1
  fi

  _tmpdir="$(mktemp -d)"
  _err="${_tmpdir}/openssl.err"

  # Config file is more portable than -addext across LibreSSL / OpenSSL.
  cat >"${_tmpdir}/openssl.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_codesign
prompt = no

[req_distinguished_name]
CN = ${EPHEMERAL_CERT_NAME}
O = Peak CI
OU = Xcode Cloud

[v3_codesign]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

  if ! openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "${_tmpdir}/key.pem" \
      -out "${_tmpdir}/cert.pem" \
      -days 2 \
      -config "${_tmpdir}/openssl.cnf" \
      2>"${_err}"; then
    echo "error: openssl failed to create ephemeral codesigning cert" >&2
    log_sanitized_err "openssl_req" "${_err}"
    rm -rf "${_tmpdir}"
    return 1
  fi

  _p12_pw="$(openssl rand -hex 16)"
  if ! export_ephemeral_p12 "${_tmpdir}" "${_p12_pw}"; then
    rm -rf "${_tmpdir}"
    return 1
  fi

  if ! import_ephemeral_identity "${_tmpdir}" "${_p12_pw}"; then
    echo "error: security import of ephemeral cert failed" >&2
    rm -rf "${_tmpdir}"
    return 1
  fi

  # Self-signed certs often do not appear in `find-identity -p codesigning`
  # (untrusted). Prove usability with a codesign probe instead.
  if ! ephemeral_identity_can_sign; then
    echo "error: ephemeral cert imported but codesign probe failed" >&2
    security find-identity -v 2>&1 | sed 's/^/  /' >&2 || true
    security find-certificate -a -c "${EPHEMERAL_CERT_NAME}" 2>&1 | sed 's/^/  /' >&2 || true
    rm -rf "${_tmpdir}"
    return 1
  fi

  rm -rf "${_tmpdir}"

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

  if is_ci; then
    # Build - iOS with empty/- identities never installs Distribution certs —
    # skip the long wait and go straight to ephemeral.
    _skip_wait=0
    if [ "${PREPARE_IDENTITY_ONLY:-}" = "1" ]; then
      _skip_wait=1
    elif is_build_only_action && build_env_identities_empty; then
      echo "warning: Build-only with empty CODE_SIGN identities; skipping keychain wait → ephemeral" >&2
      _skip_wait=1
    fi

    if [ "${_skip_wait}" -eq 0 ]; then
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
# Never fail the Cloud build from this path — signing happens in the build
# phase after SPM resolve (xcframework is usually absent at pre_xcodebuild).
if [ "${PREPARE_IDENTITY_ONLY:-}" = "1" ]; then
  _prep="$(resolve_identity || true)"
  if [ -z "${_prep}" ]; then
    echo "warning: PREPARE_IDENTITY_ONLY — no codesigning identity yet; build phase will retry after SPM resolve" >&2
    exit 0
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
    # A: Build-only (or empty/- identities on a non-archive action) — do not
    # fail the compile check when ephemeral import also failed.
    if is_build_only_action || { ! is_signing_required_action && build_env_identities_empty; }; then
      skip_sign_build_only
    fi
    echo "error: On Xcode Cloud Archive/install, signing is required for TestFlight/TMS-91065." >&2
    echo "error: Prefer workflow action Archive - iOS (Distribution identity)." >&2
    echo "error: Confirm automatic signing for team 49BZ7S974W and re-run the workflow." >&2
    echo "error: If ephemeral import failed above, check ephemeral_import= / import_* log lines." >&2
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
