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
   with “CNAME record not set”, create DNS in the `peakapp.site` zone:

   | Type | Name | Target | Proxy |
   | --- | --- | --- | --- |
   | CNAME | `app` | `peak-web-dq7.pages.dev` | Proxied |

   (Wrangler OAuth may lack `zone` write — use the Cloudflare DNS UI if
   `wrangler` / API returns Authentication error.)

3. **Privy** → App → Allowed origins:
   - `https://app.peakapp.site`
   - `http://localhost:3000`
   - `https://<deployment>.peak-web.pages.dev` (or project `*.pages.dev`)
4. Optional Railway: `CORS_ORIGINS=https://app.peakapp.site` — only needed if
   something calls the API from the browser without the `/api/peak/*` proxy.
   The Next app does not need this.

## Verify

| URL | Expect |
| --- | --- |
| `https://peakapp.site/` | Original marketing landing |
| `https://peakapp.site/legal/privacy` | 200 |
| `https://peakapp.site/invite/TESTCODE` | 200 (Pages Function) |
| `https://peakapp.site/.well-known/apple-app-site-association` | `Content-Type: application/json` |
| `https://app.peakapp.site/markets` | 200, live markets |
| `https://app.peakapp.site/event/<slug>` | 200, trade UI |

Landing “Launch app” buttons must open `https://app.peakapp.site`.

## Rollback

Re-point nothing on the apex if you never moved it. To undo web only: remove
the `app.peakapp.site` custom domain from `peak-web`, or redeploy a prior
Pages deployment. Landing rollback is a separate `wrangler pages deploy
website --project-name peak-website` of a known-good `website/` tree.
