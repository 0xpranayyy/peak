# Peak web

Trading client on **`app.peakapp.site`** (Next.js → Cloudflare Pages `peak-web`).
Marketing landing stays on the apex (`peakapp.site` → `peak-website` /
`website/`). Same Peak backend as iOS (`api.peakapp.site`), same public edge
Worker for Gamma/CLOB/geo (`edge.peakapp.site`).

**No mock / demo / placeholder trading data.** If the API has nothing, the UI
shows an empty state. Marketing copy lives on the apex, not here.

| Route | What it is |
| --- | --- |
| `/` | Redirect → `/markets` |
| `/markets` | Live feed, sort + category filters, search |
| `/event/[slug]` | Market detail + trade ticket + watchlist toggle |
| `/positions` | Cash, deposit, open orders + cancel, positions, activity |
| `/portfolio` | Redirect → `/positions` |
| `/watchlist` | Local watchlist (event IDs in `localStorage`, keyed by Privy user id) |
| `/settings` | Account, wallet, network, geo, sign out, legal links |
| `/search` | Search (`noindex`) |
| `/invite/[code]` | Referral landing |
| `/legal/*` | Privacy, Terms, Support mirrors |
| `/api/peak/*` | Same-origin proxy → Peak trading API |

## Auth and trading

- **Privy only** on web (email / Google / Apple / wallet). No seed import in
  the browser — that path stays iOS-only. See
  [`docs/WEB_CLIENT.md`](../docs/WEB_CLIENT.md).
- After login: `POST /auth/session` (path `new`), then `POST /trading/setup`
  when deploy is needed.
- Orders: `POST /orders/prepare` → browser submits prepared body to CLOB.
- Ticket: market (FOK buy / FAK sell) + limit (GTC); live bid/ask from edge.
- Geo banner from Worker `GET /geo`; buys disabled when blocked / close-only.

## Develop

```bash
cd web
cp .env.example .env.local
# Set NEXT_PUBLIC_PRIVY_APP_ID from Privy Dashboard
npm install
npm run dev
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `NEXT_PUBLIC_PRIVY_APP_ID` | — | Required for sign-in |
| `NEXT_PUBLIC_PRIVY_CLIENT_ID` | — | Optional Privy client id |
| `NEXT_PUBLIC_PEAK_EDGE_URL` | `https://edge.peakapp.site` | Gamma / CLOB / geo |
| `PEAK_API_URL` | `https://api.peakapp.site` | Upstream for `/api/peak/*` |
| `PEAK_WEB_PROXY_SECRET` | — | Shared with Worker; forwards browser CF country |

## Deploy

```bash
npm run pages:deploy
```

Full runbook: [`docs/WEB_CLIENT.md`](../docs/WEB_CLIENT.md). Do **not** attach
apex `peakapp.site` to `peak-web`.
