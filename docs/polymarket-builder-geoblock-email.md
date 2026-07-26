# Draft: Polymarket Builder support — server-side geoblock

## Short version (Telegram / Discord builder channel)

> Hey — Builder question about the CLOB geoblock for server-side integrations.
>
> We're building a native iOS Polymarket client (Builder key + Relayer, CLOB V2 /
> pUSD). Orders are signed and submitted from our backend, since the user's key
> lives in a Privy server wallet.
>
> Looks like the geoblock is evaluated against the IP the request comes from, so
> every order gets judged by our server's location instead of the user's — which
> means users in *permitted* countries get "Trading restricted in your region".
>
> We already resolve each user's country at the edge and block restricted regions
> in both the app and our API, so this isn't about bypassing anything — it's that
> our own server's location is wrongly blocking users who are allowed to trade.
>
> How are Builder backends meant to handle this? Is there an allowlist, a way to
> pass the end user's location with an order, or is the expected pattern that the
> client submits the signed order directly to CLOB and the backend only signs?
> Happy to restructure if that's the recommendation 🙏

Keep the full email below for a support inbox or a named Builder contact.

---

## Full version (email)

Send to Polymarket Builder / developer support (or your Builder contact).
Keep it short; the specific question is in bold.

---

**Subject:** Builder integration — how should a server-side backend handle the CLOB geoblock?

Hi,

I'm building Peak, a native iOS client for Polymarket. We're set up as a Builder
(Builder API key + Relayer configured) and using CLOB V2 with pUSD.

Our architecture places orders from a backend rather than from the device: the
user's signing key lives in a Privy server wallet, so the backend builds, signs
and submits the order via `@polymarket/clob-client-v2`.

The problem is that CLOB appears to evaluate the geoblock against the IP the
request originates from — which for us is always the backend, never the user.
The result is that **every** order is judged by our server's location instead of
the customer's, so users in permitted countries are rejected with:

> Trading restricted in your region, please refer to available regions

We host on Railway, and all four of its regions look unusable for this:

| Region | Location | Status |
| --- | --- | --- |
| us-west / us-east | USA | Restricted |
| eu-west | Amsterdam, NL | Restricted (KSA decision, Jan 2026) |
| southeast-asia | Singapore | Close-only — cannot open positions |

**So my question: how are Builder integrations expected to handle this?**
Specifically:

1. Is there an allowlist or Builder-specific handling for backend IPs, given that
   any server-side integration necessarily has a fixed datacenter IP?
2. Is there a supported way to pass the end user's location/IP with an order (a
   header or field) so eligibility is assessed per user rather than per server?
3. If neither, is the expected pattern that the **client** submits the signed
   order directly to CLOB, with the backend only signing? Happy to restructure
   that way if it's what you recommend.
4. Are there hosting regions you'd consider appropriate for a Builder backend?

For context on how we handle eligibility: we already resolve each user's country
at the edge (Cloudflare) and block restricted regions both in the app and in our
API before an order is ever attempted — users in restricted regions are refused
by us, not just by you. I'm not looking to work around the restrictions; I'm
trying to stop our own server's location from wrongly blocking users who are
permitted to trade.

Happy to share more detail on the integration if useful.

Thanks,
Pranay
Peak — Builder API key: <first 6 chars only, e.g. abc123…>
