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
| Email / Apple / Google sign-in | Ready | Privy; native SIWA entitlement omitted for Personal Team (see `docs/PRODUCTION.md`) |
| Path choice (new vs existing) | Ready | Links account wallet via Gamma profile |
| Magic / social Polymarket (no key) | View-only | Paste profile address — no live trading without a key |
| Live buy / sell / cancel (per user) | Works where permitted | Verified against production Builder + Relayer; blocked regions are gated client-side (see Regions) |
| Deposit wallet deploy | Credentials live | Builder / Relayer / RPC configured on the hosted API |
| Production HTTPS backend | Live | Railway behind `api.peakapp.site`; `PEAK_BACKEND_URL` + `/legal/*` in Info.plist |
| App Store packaging | Prep checklist | See [docs/APP_STORE.md](docs/APP_STORE.md); SIWA entitlement only on a paid team; legal still draft until counsel |

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
- Manual E2E / TestFlight smoke A+B against hosted API — [docs/PRODUCTION.md](docs/PRODUCTION.md), [docs/APP_STORE.md](docs/APP_STORE.md)
- Paid Apple Developer team for TestFlight / App Store; legal counsel before treating `/legal/*` as final

## Production checklist

See [docs/PRODUCTION.md](docs/PRODUCTION.md) and [docs/APP_STORE.md](docs/APP_STORE.md).

## APIs

- Gamma / CLOB public reads (`/prices-history`, `/book`, `/midpoint`, `/price`) / Data API / market WebSocket
- Authenticated CLOB via `backend/` proxy only
