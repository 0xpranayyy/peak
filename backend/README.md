# Peak trading API

Supports two modes:

1. **Privy (recommended)** — each user signs in on iOS; the backend verifies their Privy access token, resolves their Polymarket account wallet, and (once Builder + Relayer keys are set) deploys Deposit Wallets / posts CLOB orders.
2. **Legacy** — one `PRIVATE_KEY` / `FUNDER_ADDRESS` + shared `APP_TOKEN` for local solo testing.

## User paths

| Path | Who | What Peak does |
| --- | --- | --- |
| `new` | First-time / social traders | Privy embedded signer → deploy **Deposit Wallet** when Builder + Relayer keys exist |
| `existing` | MetaMask / Rainbow / Rabby | Prefer **Connect wallet** + Privy SIWE on iOS; resolve Proxy/Safe via Gamma → sync portfolio. Key/seed import is fallback when WC fails |
| View-only | Magic/Google Polymarket (no exportable key) | Paste profile address → Data API positions only — **no live trading** against that account |

See [Wallets and Authentication](https://docs.polymarket.com/trading/deposit-wallets). Live trading stays blocked until Builder / Relayer secrets and a hosted HTTPS API are configured (see [docs/PRODUCTION.md](../docs/PRODUCTION.md)).

## Setup

```bash
cd backend
cp .env.example .env
# Minimum for Privy mode:
#   PRIVY_APP_ID, PRIVY_APP_SECRET
# When you have them (live trading):
#   POLYMARKET_BUILDER_API_KEY, POLYMARKET_BUILDER_SECRET, POLYMARKET_BUILDER_PASSPHRASE
#   RELAYER_API_KEY, RELAYER_API_KEY_ADDRESS
#   POLY_BUILDER_CODE (optional attribution)
# When Privy requires signed wallet RPC:
#   PEAK_PRIVY_AUTH_KEY   # Dashboard → Wallets → Authorization keys → New key
# Legacy solo proxy (optional):
#   APP_TOKEN             # openssl rand -hex 32 — set on host too if used in prod
#   PRIVATE_KEY, FUNDER_ADDRESS
npm install
npm start
```

Health (no auth):

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/health/live
```

Legal / support: API routes **301-redirect** to Cloudflare Pages (`website/legal/*`). Point Info.plist at the Pages URLs (see `docs/PRODUCTION.md`); do not serve draft HTML from this API.

```bash
curl -sI http://127.0.0.1:8080/legal/privacy   # → 301 to Pages
curl -sL -o /dev/null -w '%{http_code}\n' https://peakapp.site/legal/privacy/
```

| After Pages is live | Info.plist key |
| --- | --- |
| `https://peakapp.site/legal/privacy` | `PEAK_PRIVACY_URL` |
| `https://peakapp.site/legal/terms` | `PEAK_TERMS_URL` |
| `https://peakapp.site/legal/support` | `PEAK_SUPPORT_URL` |

### Device smoke in 5 steps

1. `npm start` — confirm `/health` shows `privy` / `builder` / `relayer` as expected.
2. On a **physical iPhone**, set Portfolio → Account → Trading backend to `http://<Mac-LAN-IP>:8080` (not `127.0.0.1`). Simulator can use `http://127.0.0.1:8080`.
3. Privy Dashboard: **Wallet** login + bundle `com.pranay.peak` + URL scheme `peak` (`peak://` for WalletConnect).
4. Xcode → Debug run on device (same Wi‑Fi as Mac).
5. Connect wallet or social sign-in → pick trading path → confirm the app reaches this API (no “backend not configured”).

Full production E2E: [docs/PRODUCTION.md](../docs/PRODUCTION.md).

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Connectivity flags: `ok`, `legacy`, `privy`, `privyAuthKey`, `builder`, `relayer`, `sessions`, `sessionStore`, `cors`, `uptimeSec` |
| GET | `/health/live` | Liveness probe (minimal) |
| GET | `/legal/privacy` | 301 → Pages privacy |
| GET | `/legal/terms` | 301 → Pages terms |
| GET | `/legal/support` | 301 → Pages support |
| POST | `/auth/session` | Privy: `{ eoa, path?, accountWallet? }` → resolve book |
| POST | `/auth/import-wallet` | One-time key/seed → Privy TEE + existing path |
| POST | `/trading/resolve` | Re-resolve account wallet / type |
| POST | `/trading/setup` | Deploy Deposit Wallet or finalize existing (needs Builder) |
| GET | `/portfolio` | Positions for **account wallet** (not raw EOA when proxy exists) |
| GET | `/activity` | Recent activity |
| GET | `/orders` | Open orders + trades |
| POST | `/orders` | Place order |
| DELETE | `/orders/:id` | Cancel |
| POST | `/deposit-address` | Bridge deposit addresses for the account wallet |

Auth: `Authorization: Bearer <Privy access token>` or legacy `APP_TOKEN` (must match host env when using legacy mode).

## Env vars worth knowing

| Var | Role |
| --- | --- |
| `PEAK_PRIVY_AUTH_KEY` | Privy authorization **private** key for server wallet RPC. Dashboard → **Wallets** → **Authorization keys** → **New key**. |
| `APP_TOKEN` | Legacy app↔backend shared secret (`Bearer`). Generate: `openssl rand -hex 32`. Set on host if legacy mode is used in prod. |
| `CORS_ORIGINS` | Browser allow-list. **Empty = CORS off** (correct for iOS). Production browser tools: `https://…` only; local optional `http://localhost:…`. `*` rejected. |

## Production notes (host yourself)

Do **not** commit `.env`. Put secrets in the host’s environment UI (same names as `.env.example`).

### Hardening (enabled in code)

- **Rate limits** — `RATE_LIMIT_MAX` / `RATE_LIMIT_WINDOW_MS` (health skipped)
- **Request logs** — method, path, status, duration only (no tokens, keys, or bodies)
- **CORS** — off by default; set `CORS_ORIGINS` to an explicit HTTPS allow-list if a browser client needs it
- **Sessions** — durable file store (`.sessions.json` or `PEAK_SESSION_STORE`); mount a volume so restarts keep Privy session metadata
- **Trust proxy** — set `TRUST_PROXY=1` behind Fly / Railway / Render so rate limits see the real client IP
- **Legal pages** — served on the API origin so App Store URLs share the same HTTPS host

### Docker

```bash
cd backend
docker build -t peak-api .
docker run --rm -p 8080:8080 --env-file .env \
  -e PEAK_SESSION_STORE=/data/sessions.json -v peak-sessions:/data \
  peak-api
```

### Fly.io / Railway / Render (checklist — no deploy required from this repo)

1. Create an app from `backend/` (Dockerfile present).
2. Set env vars from `.env.example` (Privy + Builder + Relayer + `TRUST_PROXY=1`; add `PEAK_PRIVY_AUTH_KEY` / `APP_TOKEN` as needed).
3. Attach a persistent volume and set `PEAK_SESSION_STORE` to a path on that volume.
4. Health check path: `/health` or `/health/live`.
5. Point the iOS Release build at the HTTPS URL via `PEAK_BACKEND_URL` (Release rejects localhost and non-HTTPS).
6. Set `PEAK_PRIVACY_URL` / `PEAK_TERMS_URL` / `PEAK_SUPPORT_URL` to `https://YOUR_HOST/legal/...`.

### Fly.io template

`fly.toml` is a starting point (rename `app`, create the Fly app, set secrets, optionally mount a volume for sessions). See comments in that file.

Rotate any credentials that were ever pasted into chat before going live.
