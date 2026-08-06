# Peak web

Landing, market browsing, and Privy-authenticated trading on one Next.js app
(Cloudflare Pages). Same Peak backend as iOS (`api.peakapp.site`), same public
edge Worker for Gamma/CLOB/geo (`edge.peakapp.site`).

| Route | What it is |
| --- | --- |
| `/` | Landing — pitch, live trending strip, CTAs |
| `/markets` | Full feed, with sort and category filters |
| `/event/[slug]` | Market detail + trade ticket (SSR metadata) |
| `/portfolio` | Cash, deposit wallet, positions (auth) |
| `/search` | Search (`noindex`) |
| `/invite/[code]` | Referral landing |
| `/legal/*` | Privacy, Terms, Support (static) |
| `/api/peak/*` | Same-origin proxy → Peak trading API |
| `/.well-known/apple-app-site-association` | Universal links |

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
work without setting Railway `CORS_ORIGINS`. You can still allow-list
`https://peakapp.site` / `http://localhost:3000` on the API later if you want
direct browser calls.

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

## Deploy — verify before switching the domain

Do **not** point `peakapp.site` at this on the first deploy. Ship it to its own
project, check the three items below on the `pages.dev` URL, then move the domain.

```bash
npm run pages:deploy          # creates/updates the `peak-web` Pages project
```

Then, on the deployment's `*.pages.dev` URL:

```bash
curl -sI  https://<deployment>.pages.dev/.well-known/apple-app-site-association | grep -i content-type
curl -so /dev/null -w '%{http_code}\n' https://<deployment>.pages.dev/legal/privacy
curl -so /dev/null -w '%{http_code}\n' https://<deployment>.pages.dev/invite/TESTCODE
```

Expect `application/json`, `200`, `200`. Only then add the custom domain
`peakapp.site` to `peak-web` in the Cloudflare dashboard.

Also add the Pages origin (and `https://peakapp.site` once cut over) in Privy
Dashboard → allowed origins.

**Rollback:** the previous site is untouched in `website/` and still deployable
as the `peak-website` project.

## Three things that must not break

1. **`/.well-known/apple-app-site-association`** — universal links.
2. **`/legal/*`** — App Store review points at these URLs.
3. **`/invite/[code]`** — Next route; do not re-add `web/functions/`.

## Gamma quirks

`lib/gamma.ts` normalises numbers-as-strings and JSON-string arrays for
`outcomes` / `outcomePrices` / `clobTokenIds` (same as iOS Flexible* helpers).
