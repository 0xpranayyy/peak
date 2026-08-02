# Peak

Native SwiftUI iOS app for [Polymarket](https://polymarket.com) prediction markets.

Minimal, clean, Apple HIG / Liquid Glass (iOS 26 gated with `#available`).

## Tabs

Markets · Search · Portfolio · Watchlist · Settings

## Status (honest)

| Area | Status | Notes |
| --- | --- | --- |
| Browse markets / charts / order book | Ready | Gamma + CLOB via the `worker/` edge proxy |
| Connect wallet + Privy SIWE | Code ready | Needs Reown `WALLETCONNECT_PROJECT_ID` + Privy Dashboard **Wallet** login |
| Email / Apple / Google sign-in | Ready | Privy; native SIWA entitlement still omitted (re-add on paid team when needed — `docs/APP_STORE.md`) |
| Path choice (new vs existing) | Ready | Links account wallet via Gamma profile |
| Magic / social Polymarket (no key) | View-only | Paste profile address — no live trading without a key |
| Live buy / sell / cancel (per user) | Works where permitted | Verified against production Builder + Relayer; blocked regions are gated client-side (see Regions) |
| Deposit wallet deploy | Credentials live | Builder / Relayer / RPC configured on the hosted API |
| Production HTTPS backend | Live | Railway behind `api.peakapp.site`; legal URLs point at Pages (`peak-website-88n.pages.dev`) while apex SSL is 525 |
| App Store packaging | Ready to archive | Paid team `49BZ7S974W`; see [docs/APP_STORE.md](docs/APP_STORE.md). Device E2E / TestFlight upload still required |

**Not claimed live yet:** an end-to-end MetaMask / social *order* has not been placed from this repo. Sign-in, wallet import, account linking, portfolio and live balance are verified against production.

## Regions

Polymarket geoblocks restricted regions and rejects their orders. Peak resolves
eligibility up front via the edge Worker's `/geo` (Cloudflare sees the real
client IP; the API backend only ever sees its own) and disables the affected
actions with an explanation, instead of letting an order fail after a round
trip. Close-only regions can still exit positions.

The country list in `worker/src/index.js` is a point-in-time snapshot and will
drift as regulators move — CLOB's own rejection stays authoritative. Peak does
not attempt to circumvent these restrictions.

## Open in Xcode

1. Open `Peak.xcodeproj` in Xcode 16+ (iOS 18+).
2. Copy `Peak/PrivySecrets.local.example.plist` → `Peak/PrivySecrets.local.plist` and fill Privy + `WALLETCONNECT_PROJECT_ID` (Reown Cloud). Keep secrets out of tracked `Info.plist`.
3. Select a simulator or device → set Development Team → ⌘R.
4. Local trading API (DEBUG only): `cd backend && cp .env.example .env && npm start` — simulator may default to `http://127.0.0.1:8080`; **physical device** must use `http://<Mac-LAN-IP>:8080` under Portfolio → Account → Trading backend.

Device smoke (5 steps): [docs/PRODUCTION.md](docs/PRODUCTION.md#device-smoke-in-5-steps-debug-local-api) · [backend/README.md](backend/README.md#device-smoke-in-5-steps).

## Sign in & trading

1. **Connect wallet** (primary) — WalletConnect → Privy SIWE for existing MetaMask / Rainbow users.
2. **Email / Apple / Google** — Privy embedded wallet for new traders.
3. After sign-in, choose **new** or **existing** Polymarket path (or import a key/seed as fallback).
4. Portfolio sync uses the Polymarket **account wallet** (Proxy / Safe / Deposit), not just the EOA.
5. Magic / Google-only Polymarket accounts without an exportable key: **view-only** via pasted profile address.

When you have Builder / Relayer / API secrets, drop them in `backend/.env` (see `backend/.env.example`). No App Store resubmit needed for server-only secrets.

Release builds do **not** auto-use localhost (code rejects `127.0.0.1` / `localhost` outside DEBUG). Set `PEAK_BACKEND_URL` (HTTPS) in `Peak/Info.plist`.

## External blockers (before “production ready”)

- Privy + Reown on device; Builder + Relayer + RPC on the server (host secrets)
- Manual E2E / TestFlight smoke A+B (+ B2) against hosted API — [docs/PRODUCTION.md](docs/PRODUCTION.md), [docs/APP_STORE.md](docs/APP_STORE.md)
- ~~Paid Apple Developer team; legal counsel on `/legal/*`~~ — both done (2026-07-27)
- Cloudflare: fix apex `peakapp.site` SSL (currently 525); legal links temporarily use Pages hostname

## Production checklist

See [docs/PRODUCTION.md](docs/PRODUCTION.md), [docs/APP_STORE.md](docs/APP_STORE.md), and [docs/RELEASE.md](docs/RELEASE.md) (ongoing TestFlight / release cadence). Post–iOS web landing + client plan: [docs/WEB_CLIENT.md](docs/WEB_CLIENT.md).

## Shipping a build

On an Xcode **beta** Mac, use [docs/XCODE_CLOUD.md](docs/XCODE_CLOUD.md) to Archive with a public/GM Xcode for TestFlight.

Signing is configured (team `49BZ7S974W`, `com.pranay.peak` + `.widget`,
automatic). A Release archive builds clean.

**Bump the build number first.** App Store Connect rejects a build number it
has already accepted, and `ExportOptions.plist` deliberately does not let Xcode
rewrite it:

```
CURRENT_PROJECT_VERSION   # in Peak.xcodeproj — bump for every upload
MARKETING_VERSION         # 1.1 — bump only for a user-visible release
```

Then:

```bash
xcodebuild archive -project Peak.xcodeproj -scheme Peak \
  -destination 'generic/platform=iOS' -archivePath build/Peak.xcarchive

xcodebuild -exportArchive -archivePath build/Peak.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
```

The archive signs "Apple Development"; the export step re-signs it with the
Apple Distribution certificate. That is the step that needs the paid account,
and it will prompt for App Store Connect credentials the first time.

Upload with Transporter, or:

```bash
xcrun altool --upload-app -f build/export/Peak.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

An app record for **`com.pranay.peak`** must already exist in App Store Connect —
upload fails with an unhelpful error if it does not. When creating the New App,
pick that bundle ID (not Asteria / not the widget).

If Connect rejects with **TMS-91065** (PrivySDK / SwiftyJSON missing signature),
see [docs/APP_STORE.md](docs/APP_STORE.md#tms-91065--privysdk--swiftyjson-missing-signature).
Peak’s **Sign PrivySDK XCFramework** build phase + `scripts/sign-privy-xcframework.sh`
work around Privy 2.14.0 shipping an unsigned XCFramework.

### Sentry symbols

Peak links the SPM product **`Sentry-Dynamic`** (sentry-cocoa ≥ 8.x), not the
static `Sentry` binary. The static XCFramework ships **no** `dSYMs/`; Xcode 16+
then warns *"The archive did not include a dSYM for the Sentry.framework"* on
upload. That message is a **warning** (TestFlight / App Store upload still
proceeds). Dynamic linking embeds `Sentry.framework` and its matching
`Sentry.framework.dSYM` in the archive so Apple’s symbol upload and the
scheme post-action both see it.

`uploadSymbols` (in `ExportOptions.plist`) sends dSYMs to Apple, not to
Sentry — those are two separate destinations. The Peak scheme's Archive action
has a **Post-action** ("Upload Debug Symbols to Sentry") that handles the
Sentry side automatically on every Release archive. One-time local setup:

```bash
brew install getsentry/tools/sentry-cli
cp sentry.properties.example sentry.properties   # gitignored, holds a real auth token
```

Fill in `defaults.org`, `defaults.project` (from your Sentry project URL) and
`auth.token` (sentry.io → Settings → Auth Tokens, scoped to `project:releases`
or the newer "Debug Files: Write"). Nothing else to run — the next `Product →
Archive` uploads dSYMs as part of the build.

The phase is deliberately non-fatal: missing `sentry.properties`, missing
`sentry-cli`, or an upload failure all print a warning and let the build
continue rather than blocking a release over a symbolication gap. Reporting
itself is Release-only by design (`CrashReporting.start` disables itself in
DEBUG), so an empty Sentry dashboard after a Debug run is expected, not a
fault.

## APIs

- Gamma / CLOB public reads (`/prices-history`, `/book`, `/midpoint`, `/price`) / Data API / market WebSocket
- Authenticated CLOB via `backend/` proxy only
