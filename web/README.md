# Peak web

Browse markets and trade via Privy on **`app.peakapp.site`** (Next.js →
Cloudflare Pages project `peak-web`). Marketing landing stays on the apex
(`peakapp.site` → Pages project `peak-website` / `website/`). Same Peak backend
as iOS (`api.peakapp.site`), same public edge Worker for Gamma/CLOB/geo
(`edge.peakapp.site`).

| Route | What it is |
| --- | --- |
| `/` | Web client home — pitch + trending markets |
| `/markets` | Full feed, with sort and category filters |
| `/event/[slug]` | Market detail + trade ticket (SSR metadata) |
| `/portfolio` | Cash, deposit wallet, positions (auth) |
| `/search` | Search (`noindex`) |
| `/invite/[code]` | Referral landing (apex `/invite/*` remains canonical for Universal Links) |
| `/legal/*` | Privacy, Terms, Support mirrors (canonical copy on apex) |
| `/api/peak/*` | Same-origin proxy → Peak trading API |
| `/.well-known/apple-app-site-association` | Mirror only — live Universal Links stay on apex |

## Auth and trading

- **Privy only** on web (email / Google / Apple / wallet). Peak never asks for a
  private key or seed phrase in the browser — that path stays iOS-only. See
  [`docs/WEB_CLIENT.md`](../docs/WEB_CLIENT.md).
- After login the client calls `POST /auth/session` (path `new`), then
  `POST /trading/setup` when deploy is needed.
- Orders use the iOS flow: `POST /orders/prepare` (Peak signs) → browser
  submits the prepared body to CLOB so geoblock sees the user IP.
- Geo banner uses Worker `GET /geo`. Buys are disabled when status is
  `blocked` or `close_only`.

Authenticated API calls go through `/api/peak/*` so local and Pages deploys
work without setting Railway `CORS_ORIGINS`. Optional allow-list later:
`https://app.peakapp.site` / `http://localhost:3000`.

## Develop

```bash
cd web
cp .env.example .env.local
# Set NEXT_PUBLIC_PRIVY_APP_ID (and optional NEXT_PUBLIC_PRIVY_CLIENT_ID)
# from the Privy Dashboard — same app as iOS is fine.
# Add http://localhost:3000 as an allowed origin in Privy.
npm install
npm run dev
```

Optional env:

| Variable | Default | Purpose |
| --- | --- | --- |
| `NEXT_PUBLIC_PRIVY_APP_ID` | — | Required for sign-in |
| `NEXT_PUBLIC_PRIVY_CLIENT_ID` | — | Optional Privy client id |
| `NEXT_PUBLIC_PEAK_EDGE_URL` | `https://edge.peakapp.site` | Gamma / geo |
| `PEAK_API_URL` | `https://api.peakapp.site` | Upstream for `/api/peak/*` |

Without `NEXT_PUBLIC_PRIVY_APP_ID`, browse still works; Sign in explains the missing env.

## Deploy

Full runbook: [`docs/WEB_CLIENT.md`](../docs/WEB_CLIENT.md) § Deploy.

```bash
# From web/, with NEXT_PUBLIC_* set in the shell or .env.local (build-time).
npm run pages:deploy          # creates/updates the `peak-web` Pages project
```

Then:

1. Cloudflare Pages → `peak-web` → Settings → Compatibility flags → add
   **`nodejs_compat`** (Production + Preview). Without it routes 500.
2. Custom domains → add **`app.peakapp.site`** (do **not** move apex off
   `peak-website`).
3. Privy Dashboard → Allowed origins → add `https://app.peakapp.site`,
   `http://localhost:3000`, and the `*.pages.dev` preview host.

Smoke on the deployment URL (then on `https://app.peakapp.site`):

```bash
curl -so /dev/null -w '%{http_code}\n' https://app.peakapp.site/markets
curl -so /dev/null -w '%{http_code}\n' https://peakapp.site/   # still marketing
curl -sI  https://peakapp.site/.well-known/apple-app-site-association | grep -i content-type
```

**Rollback:** leave `peak-website` on apex. Remove `app.peakapp.site` from
`peak-web` or redeploy a known-good Pages deployment.

## Three things that must not break (apex)

1. **`/.well-known/apple-app-site-association`** on `peakapp.site` — Universal Links.
2. **`/legal/*`** on `peakapp.site` — App Store review URLs.
3. **`/invite/[code]`** on `peakapp.site` — Pages Function in `website/functions/`.

## Gamma quirks

`lib/gamma.ts` normalises numbers-as-strings and JSON-string arrays for
`outcomes` / `outcomePrices` / `clobTokenIds` (same as iOS Flexible* helpers).
