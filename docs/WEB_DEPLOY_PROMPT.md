# Deploy runbook: Peak web client beside the landing

Marketing stays on **`https://peakapp.site`** (`website/` → Pages project
`peak-website`). The Next trading client ships on
**`https://app.peakapp.site`** (`web/` → Pages project `peak-web`).

Do **not** point the apex custom domain at `peak-web`. That would replace the
landing page.

## One-shot deploy (from repo root)

```bash
# 1) Landing CTAs (Launch app → app.peakapp.site) — use --branch main for Production
npx wrangler pages deploy website --project-name peak-website --branch main

# 2) Web client — NEXT_PUBLIC_* must be present at build time
cd web
# Ensure .env.local has NEXT_PUBLIC_PRIVY_APP_ID (and optional CLIENT_ID)
npm install
npm run pages:build
npx wrangler pages deploy .vercel/output/static --project-name peak-web --branch main
```

## After first `peak-web` create

1. **Dashboard** → Pages → `peak-web` → Settings → Functions → Compatibility
   flags → **`nodejs_compat`** for Production and Preview.
2. **Custom domains** → Add `app.peakapp.site`. If verification stays pending
   with “CNAME record not set”, create DNS in the `peakapp.site` zone
   (**Cloudflare Dashboard → DNS** — Wrangler OAuth is typically zone
   **read-only** and API create returns Authentication error):

   | Type | Name | Target | Proxy |
   | --- | --- | --- | --- |
   | CNAME | `app` | `peak-web-dq7.pages.dev` | Proxied |

   Confirm with `dig +short app.peakapp.site CNAME` → `peak-web-dq7.pages.dev.`
   and `curl -so /dev/null -w '%{http_code}\n' https://app.peakapp.site/markets`
   → `200`. Apex `https://peakapp.site/` must still be marketing.

3. **Privy** → App → Allowed origins:
   - `https://app.peakapp.site` (required)
   - `https://peak-web-dq7.pages.dev` (required until custom domain Active)
   - `http://localhost:3000` (local)
   - **Not** `https://peakapp.site` when Launch app is only a link to `app.`
4. Optional Railway: `CORS_ORIGINS=https://app.peakapp.site` — only needed if
   something calls the API from the browser without the `/api/peak/*` proxy.
   The Next app does not need this.
5. **Geo through proxy (recommended):** generate a long random secret, set
   `PEAK_WEB_PROXY_SECRET` on Pages (`peak-web` Production + Preview) **and**
   as a Worker secret on `peak-edge` (`wrangler secret put PEAK_WEB_PROXY_SECRET`),
   then `cd worker && npx wrangler deploy`. Without this, prepare/submit may
   see the Pages colo country instead of the trader’s. Live CLOB submit from
   blocked regions (e.g. `IN`) still fails — smoke trade from an allowed
   region or VPN; browse / Privy session / markets still work while blocked.

## Verify

| URL | Expect |
| --- | --- |
| `https://peakapp.site/` | Original marketing landing |
| `https://peakapp.site/legal/privacy` | 200 |
| `https://peakapp.site/invite/TESTCODE` | 200 (Pages Function) |
| `https://peakapp.site/.well-known/apple-app-site-association` | `Content-Type: application/json` |
| `https://app.peakapp.site/markets` | 200, live markets |
| `https://app.peakapp.site/event/<slug>` | 200, trade UI with bid/ask |
| `https://app.peakapp.site/portfolio` | Sign-in → cash / orders / positions |

Full trading smoke: [WEB_CLIENT.md § Smoke test](WEB_CLIENT.md#smoke-test-checklist-web).

Landing “Launch app” buttons must open `https://app.peakapp.site`.

## Rollback

Re-point nothing on the apex if you never moved it. To undo web only: remove
the `app.peakapp.site` custom domain from `peak-web`, or redeploy a prior
Pages deployment. Landing rollback is a separate `wrangler pages deploy
website --project-name peak-website` of a known-good `website/` tree.
