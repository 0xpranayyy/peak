# Peak edge proxy

Cloudflare Worker that fronts all **read-only** Polymarket traffic so the app
works on networks that block Polymarket.

## Why

Indian ISPs (tested: Jio) block `*.polymarket.com` at two layers:

| Layer | Behaviour |
| --- | --- |
| DNS | `gamma-api.polymarket.com` → `49.44.79.236` (ISP block address, not Polymarket) |
| TLS | Even with correct DNS via DoH, the handshake is dropped — `curl` exit 35, SNI-based DPI |

Because the block is also at the TLS layer, **changing DNS does not fix it**.
The device must never send `polymarket.com` in an SNI. This Worker is the only
hostname the phone talks to; it reaches Polymarket from Cloudflare's network.

This is the same approach competing apps (e.g. share.xyz) use — their domain
resolves and connects normally on the same ISP that blocks Polymarket.

Side benefit: Polymarket is itself behind Cloudflare, so Worker → origin stays
on Cloudflare's backbone, and users are served from a nearby POP. This is
*faster* than reaching Polymarket directly, not merely unblocked.

## What it proxies

| Route | Upstream | Edge cache |
| --- | --- | --- |
| `/gamma/{events,markets,tags,public-search,public-profile}` | `gamma-api.polymarket.com` | 15–300s |
| `/clob/{book,books,price,midpoint,spread,prices-history,markets}` | `clob.polymarket.com` | 2–30s |
| `/data/{positions,activity,value}` | `data-api.polymarket.com` | 5s |
| `/ws/market` | `wss://ws-subscriptions-clob.polymarket.com/ws/market` | — (relay) |
| `/health` | — | — |

Paths are allowlisted, so this cannot be used as an open proxy. `GET`/`HEAD`
only. Authenticated trading is **not** proxied here — it stays on the Peak
backend, which holds the Privy/Builder/Relayer secrets.

## Deploy

1. **Register a domain and add it to Cloudflare** (free tier is enough).
   Avoid `polymarket`/`bet`/`gamble` in the name — blocklists are partly
   keyword-driven. Do **not** ship on `*.workers.dev`: shared third-party
   domains get blocked wholesale, which is exactly why the existing
   `peak-api-*.up.railway.app` host fails to resolve on Indian ISPs.

2. Uncomment and fill the route in `wrangler.toml`:

   ```toml
   [[routes]]
   pattern = "edge.<your-domain>/*"
   custom_domain = true
   ```

3. Deploy:

   ```bash
   cd worker && npx wrangler deploy
   ```

4. Verify from a blocked network:

   ```bash
   curl -s https://edge.<your-domain>/health
   curl -s "https://edge.<your-domain>/gamma/events?limit=1&closed=false" | head -c 200
   ```

5. Set `PEAK_EDGE_URL` in `Peak/Info.plist` to `https://edge.<your-domain>`.

   That single key flips the client over: `PeakAPIBase` routes Gamma, CLOB,
   Data and the market WebSocket through the edge, and skips the direct-host
   attempt entirely. Leave it empty to keep talking to Polymarket directly
   (correct for development on an unblocked network).

## Rotation

If the domain is ever added to a blocklist, deploy the same Worker on a fresh
hostname and update `PEAK_EDGE_URL`. Nothing else changes. Keeping this to one
plist key is deliberate — recovery should not need a code change.
