# Peak production checklist

Manual verification before calling the app production-ready. Do **not** invent or commit secrets. Live MetaMask / Builder E2E is listed here to run on device once credentials and hosting exist — it is not automated in-repo.

In-repo packaging sanity (no secrets): `scripts/release-sanity.sh`

## Credentials (block live trading)

Put in `backend/.env` locally, and **the same keys in the Fly / Railway / Render host env** (never commit `.env`):

### Required for Privy multi-user mode

- [ ] `PRIVY_APP_ID` / `PRIVY_APP_SECRET`
- [ ] `POLYMARKET_BUILDER_API_KEY` / `POLYMARKET_BUILDER_SECRET` / `POLYMARKET_BUILDER_PASSPHRASE`
- [ ] `RELAYER_API_KEY` / `RELAYER_API_KEY_ADDRESS`
- [ ] `POLYGON_RPC_URL`

### Server wallet signing (often required for live Privy RPC)

- [ ] `PEAK_PRIVY_AUTH_KEY` — Privy **authorization private key** used by the backend when calling wallet `signMessage` / `signTypedData`.
  - **Where:** [Privy Dashboard](https://dashboard.privy.io) → your app → **Wallets** → **Authorization keys** → **New key** → copy the **Private key** once (Privy does not store it).
  - Docs: [Create an authorization key](https://docs.privy.io/controls/authorization-keys/keys/create/key)
  - Direct: [Authorization keys page](https://dashboard.privy.io/apps?page=authorization-keys)
  - Paste into `backend/.env` as `PEAK_PRIVY_AUTH_KEY=...` and into the host secrets UI. Do not invent a fake value.

### Optional

- [ ] `POLY_BUILDER_CODE`, `POLYMARKET_RELAYER_URL`
- [ ] `TRUST_PROXY=1` on Fly / Railway / Render
- [ ] `PEAK_SESSION_STORE` on a persistent volume
- [ ] `CORS_ORIGINS` — see CORS below (usually leave empty for iOS-only)
- [ ] Mailbox / MX for `support@peakapp.site` (shown on static legal pages; not an API env var)

### Builder codes

Rotate Polymarket **builder** credentials later when you decide (user-deferred). Shipping with existing builder keys is fine until then; do not invent or commit new values.

### Legacy one-wallet proxy (optional)

- [ ] `APP_TOKEN` — shared secret; iOS sends `Authorization: Bearer <APP_TOKEN>` when not using Privy JWT.
  - **Must be set on the host too** if you enable legacy mode in production.
  - Generate a strong token: `openssl rand -hex 32`
  - Also needs `PRIVATE_KEY` + `FUNDER_ADDRESS` (+ optional CLOB creds).

iOS (`PrivySecrets.local.plist`, gitignored — **not** `Info.plist`):

- [ ] `PRIVY_APP_ID` / `PRIVY_APP_CLIENT_ID`
- [ ] `WALLETCONNECT_PROJECT_ID` from [cloud.reown.com](https://cloud.reown.com)
- [ ] Crash reporting (optional later): re-add `sentry-cocoa` SPM when Xcode package resolution is stable; `CrashReporting` hooks already exist as no-ops.

Do not put Privy or Reown secrets in tracked `Info.plist`. Backend / legal URLs for the hosted Railway API are set in `Peak/Info.plist` (see below). Local Debug can still point at a backend via `PEAK_BACKEND_URL` in Info.plist.

### Legal / Support URLs (Cloudflare Pages)

Canonical consumer pages are static HTML under `website/legal/*` on Cloudflare Pages.
`api.peakapp.site/legal/*` only **301-redirects** to that origin (`backend/legalPages.mjs`).

**SSL note (2026-07-28):** apex `https://peakapp.site` and `www` return Cloudflare **525** (origin/cert misconfigured). Until that is fixed in the Cloudflare dashboard, Info.plist and API redirects use the working Pages hostname `peak-website-88n.pages.dev`. Marketing home on the custom domain stays broken until SSL is fixed; legal links in the app do not depend on it.

| Info.plist key | Current value |
| --- | --- |
| `PEAK_BACKEND_URL` | `https://api.peakapp.site` |
| `PEAK_PRIVACY_URL` | `https://peak-website-88n.pages.dev/legal/privacy` |
| `PEAK_TERMS_URL` | `https://peak-website-88n.pages.dev/legal/terms` |
| `PEAK_SUPPORT_URL` | `https://peak-website-88n.pages.dev/legal/support` |

Support contact on those pages: `support@peakapp.site` (provision mailbox/MX when ready). Settings hides legal links only if a key is blank.

Privy Dashboard:

- [ ] Login methods: Email, Google, Apple, **Wallet**
- [ ] Bundle ID `com.pranay.peak`, URL scheme `peak` (WalletConnect redirect `peak://`)
- [ ] Authorization key created if wallet policies require signed server requests (`PEAK_PRIVY_AUTH_KEY`)

## CORS (local vs production)

| Environment | `CORS_ORIGINS` | Behavior |
| --- | --- | --- |
| Local / iOS Debug | unset / empty | **CORS off** — correct default; native apps send no `Origin` |
| Production (iOS only) | unset / empty | Same — keep off |
| Production + browser admin | `https://admin.example.com` | Allow-list only; `*` and non-local `http://` rejected |

Recommended when HTTPS API is live and you need a browser tool: `CORS_ORIGINS=https://your-admin.example.com` (comma-separate multiple). For local browser tooling only: `http://localhost:3000` is allowed; prefer leaving empty otherwise.

## Device smoke in 5 steps (Debug, local API)

Use this once `PrivySecrets.local.plist` and `backend/.env` (Privy + Builder + Relayer + RPC) are filled. No hosting required.

1. **Start API** — `cd backend && npm start` → `curl http://127.0.0.1:8080/health` should show `privy` / `builder` / `relayer` true.
2. **Point the phone at your Mac** — On a **physical device**, set Portfolio → Account → Trading backend to `http://<Mac-LAN-IP>:8080` (not `127.0.0.1`). Simulator may keep the DEBUG default `http://127.0.0.1:8080`. Mac and phone on the same Wi‑Fi; allow local network if iOS prompts.
3. **Privy Dashboard** — enable **Wallet** login; confirm bundle `com.pranay.peak` and scheme `peak`.
4. **Run Debug** — open `Peak.xcodeproj`, select your device, Development Team, ⌘R (Debug injects `NSAllowsLocalNetworking`).
5. **Smoke** — Connect wallet (MetaMask SIWE) **or** Email/Apple/Google → choose new/existing path → confirm `/health` still up and Portfolio / setup does not show “backend not configured”. Full buy/sell is checklist A/B below.

Optional local legal check: `curl -sI http://127.0.0.1:8080/legal/privacy` → `301` to Pages. Live Pages: `curl -sL -o /dev/null -w '%{http_code}\n' https://peak-website-88n.pages.dev/legal/privacy/` → `200`.

## E2E paths (run when secrets + HTTPS backend are live)



### A — New social user → deploy → trade

Code path: Privy Email / Apple / Google → choose **New account** → `POST /trading/setup` deploys Deposit Wallet when Builder + Relayer are configured.

1. Sign in with email / Apple / Google
2. Choose **New account** (new to Polymarket)
3. Confirm setup succeeds only with Builder + Relayer present (otherwise expect `503` / clear “not configured” errors)
4. Fund the deposit address from Deposit sheet → buy → sell → cancel via trade sheet



### B — MetaMask / Rainbow SIWE → same positions → sell

Code path: **Connect wallet** → WalletConnect → Privy `siwe.generateMessage` / `personal_sign` / `siwe.login` → existing path / Gamma profile → portfolio + orders.

1. **Connect wallet** → approve SIWE in MetaMask (or Rainbow / Coinbase)
2. Choose **Existing Polymarket account** if prompted (or confirm auto-resolve via Gamma `public-profile`)
3. Confirm Portfolio shows the same positions as polymarket.com for that account wallet
4. Place / cancel an order (Builder + per-user CLOB signing path required)

### B2 — Imported PM key → cash + tiny order (device retest)

After a backend deploy that includes Privy `params.typed_data` signing + existing-path import guard:

1. Sign in (email / Apple / Connect).
2. **Set up trading** → **I already trade elsewhere**.
3. If Connect alone was used: tap **Import private key** and paste the **same** key/seed as the Polymarket account (never commit secrets).
4. Confirm Portfolio **Cash** matches ~pUSD on polymarket.com (not empty with a silent failure).
5. If Cash shows “Import the private key…” → Import CTA must appear; complete import and pull-to-refresh.
6. Place a **tiny** buy (~$1) → order posts; open orders / positions update.
7. Cancel the open order if still resting.

Backend smoke without secrets: `cd backend && npm run check` (includes `smoke-trading.mjs`).

### C — Magic / Google Polymarket (no exportable key) → view-only

Code path: paste profile address on sign-in or trading-path sheet. App must **not** claim live trading against the Magic account.

1. On Polymarket Magic / Google-only account (no WalletConnect / exportable key)
2. Use **View positions with an address** (or existing-path profile address field)
3. Confirm positions load read-only
4. Confirm UI copy states trading requires a key / Connect wallet — Peak does not pretend to trade that Magic wallet



## Hosting

- [x] Deploy `backend/` with HTTPS (Railway production host live; `backend/Dockerfile` + `backend/fly.toml` template also present)
- [ ] Set secrets in the host env (from `.env.example`; never commit `.env`) — include `APP_TOKEN` if using legacy mode, and `PEAK_PRIVY_AUTH_KEY` when Privy requires it
- [x] `PEAK_BACKEND_URL` in `Peak/Info.plist` → `https://api.peakapp.site`
- [x] Legal URLs → working Pages `/legal/*` (temporarily `peak-website-88n.pages.dev`; apex SSL still broken)
- [ ] Cloudflare: fix custom-domain SSL for `peakapp.site` / `www`, then point plist + `WEBSITE_ORIGIN` back at the apex
- [ ] Confirm Release build does not use `127.0.0.1` / `localhost` / plain HTTP
  - `TradingConfigStore` accepts only non-local `https://` outside DEBUG
  - `PrivyAuthService` only auto-fills `http://127.0.0.1:8080` inside `#if DEBUG`
  - `NSAllowsLocalNetworking` is injected only for Debug via Xcode script



## App Store / TestFlight

Full checklist (SIWA re-add, Nutrition Labels, export compliance, screenshots / review notes, TestFlight smoke A+B, support mailbox): **[APP_STORE.md](APP_STORE.md)**.

Short status:

- [x] `PrivacyInfo.xcprivacy` + `ITSAppUsesNonExemptEncryption` = false (confirm encryption with counsel)
- [x] Hosted backend + working legal URLs in Info.plist (Pages hostname while apex SSL is 525)
- [x] Paid Apple Developer team (`49BZ7S974W`) + packaging / archive path ready
- [ ] Re-add SIWA entitlement on paid team when native Apple login is required (see APP_STORE.md)
- [ ] TestFlight / Connect submission + upload (manual; device required)
- [ ] Privacy Nutrition Labels in Connect aligned with PrivacyInfo
- [ ] Provision `support@peakapp.site` mailbox/MX
- [ ] TestFlight smoke A (social) + B (wallet SIWE) + B2 (imported key) against hosted API — **device E2E still required**



## Sanity checks (no secrets required)

- [x] Wallet SIWE services present (`WalletConnectAuthService`, `PeakSocketFactory`, `PeakCryptoProvider`)
- [x] Backend entrypoints present (`server.mjs`, `tradingSetup.mjs`, `sessionStore.mjs`, …)
- [x] Release does not default localhost / plain HTTP (see Hosting)
- [x] `node --check` / `npm run check` on `backend/*.mjs` (also via `scripts/release-sanity.sh`)
