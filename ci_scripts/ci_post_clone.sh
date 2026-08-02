#!/bin/sh
# Xcode Cloud: after clone, materialize gitignored PrivySecrets.local.plist from env.
# Never echo secret values. See docs/XCODE_CLOUD.md.
set -eu

PLIST="${CI_PRIMARY_REPOSITORY_PATH:-.}/Peak/PrivySecrets.local.plist"
ACTION="${CI_XCODEBUILD_ACTION:-}"

require_var() {
  _name="$1"
  eval "_val=\${${_name}:-}"
  if [ -z "$_val" ]; then
    echo "error: ${_name} is not set." >&2
    echo "error: Add it as a Secret under Xcode Cloud → Environment (see docs/XCODE_CLOUD.md)." >&2
    return 1
  fi
  return 0
}

missing=0
if [ "$ACTION" = "archive" ]; then
  require_var PRIVY_APP_ID || missing=1
  require_var PRIVY_APP_CLIENT_ID || missing=1
  require_var WALLETCONNECT_PROJECT_ID || missing=1
  if [ "$missing" -ne 0 ]; then
    echo "error: required secrets missing for Archive — refusing to continue." >&2
    exit 1
  fi
fi

# Nothing to write if no secrets are present (e.g. pure unit-test workflow without env).
if [ -z "${PRIVY_APP_ID:-}" ] && [ -z "${PRIVY_APP_CLIENT_ID:-}" ] && [ -z "${WALLETCONNECT_PROJECT_ID:-}" ] && [ -z "${SENTRY_DSN:-}" ]; then
  echo "ci_post_clone: no Privy/WalletConnect/Sentry env vars set — skipping PrivySecrets.local.plist"
  exit 0
fi

mkdir -p "$(dirname "$PLIST")"
plutil -create xml1 "$PLIST"

if [ -n "${PRIVY_APP_ID:-}" ]; then
  plutil -replace PRIVY_APP_ID -string "$PRIVY_APP_ID" "$PLIST"
fi
if [ -n "${PRIVY_APP_CLIENT_ID:-}" ]; then
  plutil -replace PRIVY_APP_CLIENT_ID -string "$PRIVY_APP_CLIENT_ID" "$PLIST"
fi
if [ -n "${WALLETCONNECT_PROJECT_ID:-}" ]; then
  plutil -replace WALLETCONNECT_PROJECT_ID -string "$WALLETCONNECT_PROJECT_ID" "$PLIST"
fi
if [ -n "${SENTRY_DSN:-}" ]; then
  plutil -replace SENTRY_DSN -string "$SENTRY_DSN" "$PLIST"
fi

# Confirm which keys were written — never print values.
_written=""
[ -n "${PRIVY_APP_ID:-}" ] && _written="${_written} PRIVY_APP_ID"
[ -n "${PRIVY_APP_CLIENT_ID:-}" ] && _written="${_written} PRIVY_APP_CLIENT_ID"
[ -n "${WALLETCONNECT_PROJECT_ID:-}" ] && _written="${_written} WALLETCONNECT_PROJECT_ID"
[ -n "${SENTRY_DSN:-}" ] && _written="${_written} SENTRY_DSN"
echo "ci_post_clone: wrote ${PLIST} with keys:${_written}"
