#!/usr/bin/env bash
# Release packaging sanity checks (no secrets required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

warn() { echo "WARN: $*"; fail=1; }
ok() { echo "OK: $*"; }

echo "== Peak release sanity =="

# Backend syntax
if command -v node >/dev/null 2>&1; then
  (cd "$ROOT/backend" && npm run check) && ok "backend npm run check" || warn "backend npm run check failed"
else
  NODE_BIN=""
  for candidate in \
    "$HOME/.local/node-v22.17.0-darwin-arm64/bin/node" \
    /opt/homebrew/bin/node \
    /usr/local/bin/node; do
    if [[ -x "$candidate" ]]; then NODE_BIN="$candidate"; break; fi
  done
  if [[ -n "$NODE_BIN" ]]; then
    (cd "$ROOT/backend" && PATH="$(dirname "$NODE_BIN"):$PATH" npm run check) \
      && ok "backend npm run check ($NODE_BIN)" \
      || warn "backend npm run check failed"
  else
    warn "node not found — skip backend syntax check"
  fi
fi

PLIST="$ROOT/Peak/Info.plist"

backend="$(/usr/libexec/PlistBuddy -c 'Print :PEAK_BACKEND_URL' "$PLIST" 2>/dev/null || true)"
if [[ -z "${backend// }" ]]; then
  ok "PEAK_BACKEND_URL empty (set after HTTPS host is live)"
else
  case "$backend" in
    https://*) ok "PEAK_BACKEND_URL is HTTPS" ;;
    *) warn "PEAK_BACKEND_URL must be https:// (got: $backend)" ;;
  esac
  case "$backend" in
    *127.0.0.1*|*localhost*) warn "PEAK_BACKEND_URL must not be localhost" ;;
  esac
fi

for key in PEAK_PRIVACY_URL PEAK_TERMS_URL PEAK_SUPPORT_URL; do
  val="$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" 2>/dev/null || true)"
  if [[ -z "${val// }" ]]; then
    ok "$key blank (add real legal page before App Store)"
  elif [[ "$val" == *peak.app* ]]; then
    warn "$key still uses placeholder peak.app — replace before App Store"
  elif [[ "$val" == https://* ]] || [[ "$val" == mailto:* ]]; then
    ok "$key set"
  else
    warn "$key should be https:// or mailto: (got: $val)"
  fi
done

if [[ -f "$ROOT/Peak/PrivacyInfo.xcprivacy" ]]; then
  ok "PrivacyInfo.xcprivacy present"
else
  warn "PrivacyInfo.xcprivacy missing"
fi

if grep -q 'applesignin' "$ROOT/Peak/Peak.entitlements" 2>/dev/null; then
  ok "Sign in with Apple entitlement present (paid team required)"
else
  ok "SIWA entitlement omitted (Personal Team–safe; add on paid team for App Store Apple login)"
fi

if [[ -f "$ROOT/backend/Dockerfile" ]]; then
  ok "backend/Dockerfile present"
else
  warn "backend/Dockerfile missing"
fi

echo
if [[ "$fail" -eq 0 ]]; then
  echo "All checks passed (or noted as waiting on user/hosting)."
  exit 0
else
  echo "One or more warnings — fix before calling Release production-ready."
  exit 1
fi
