/**
 * Peak edge proxy (Cloudflare Worker).
 *
 * Why this exists: Indian ISPs block *.polymarket.com at BOTH the DNS layer
 * (hijacked to a block address) and the TLS layer (SNI-based DPI drops the
 * handshake). Changing DNS is not sufficient — the handshake itself is killed.
 * So the device must never put "polymarket.com" in an SNI. It talks only to
 * this Worker's hostname; the Worker reaches Polymarket from Cloudflare's
 * network, where nothing is blocked.
 *
 * Bonus: Polymarket is itself behind Cloudflare, so Worker -> origin stays on
 * Cloudflare's backbone. Serving from an Indian POP is measurably faster than
 * the phone reaching Polymarket directly even on an unblocked network.
 *
 * Read-only by design. Authenticated trading stays on the Peak backend
 * (Privy JWT, Builder/Relayer secrets) — never proxy that through here.
 */

const UPSTREAMS = {
  gamma: "https://gamma-api.polymarket.com",
  clob: "https://clob.polymarket.com",
  data: "https://data-api.polymarket.com",
  // Leaderboard host — the one behind polymarket.com/leaderboard. NOT
  // data-api's /v1/leaderboard, which is a separate (daily, ~50-row) board
  // that does not match the site.
  lb: "https://lb-api.polymarket.com",
};

/**
 * NOTE: https://, not wss://. Workers' fetch() rejects the wss: scheme — an
 * outbound WebSocket is an ordinary https request carrying `Upgrade`, and the
 * runtime hands back `response.webSocket` on the 101.
 */
const WS_UPSTREAM = "https://ws-subscriptions-clob.polymarket.com/ws/market";

/**
 * Allowlist per upstream. Without this the Worker is an open proxy that anyone
 * can point at arbitrary Polymarket paths (or use to burn your quota).
 * `cacheTtl` is seconds at the edge; 0 disables edge caching.
 */
const ROUTES = {
  gamma: {
    events: 15,
    markets: 15,
    tags: 300,
    "public-search": 30,
    "public-profile": 60,
  },
  clob: {
    // Top-of-book data moves constantly — a tiny TTL still collapses
    // thundering herds on popular markets without showing stale prices.
    book: 2,
    books: 2,
    price: 2,
    midpoint: 2,
    spread: 2,
    "prices-history": 30,
    markets: 15,
  },
  data: {
    // Keyed by ?user=<address>, so the cache key is already per-wallet.
    positions: 5,
    activity: 5,
    value: 5,
  },
  lb: {
    // Public trader leaderboard by profit / volume. Cache key includes the
    // ?window= param, so each timeframe caches separately. Rankings move
    // slowly; 60s collapses load without showing a stale board.
    profit: 60,
    volume: 60,
  },
};

/**
 * Peak's own trading backend (Railway). Reached via the `api.` hostname.
 *
 * Railway's *.up.railway.app does not resolve on Indian ISP resolvers, so the
 * app cannot talk to it directly — trading failed with "Couldn't connect" even
 * though the server was healthy. A DNS-only CNAME does not help: resolving it
 * still requires the client to resolve up.railway.app. The record must be
 * Cloudflare-proxied so the client only ever resolves peakapp.site, and this
 * Worker reaches Railway from Cloudflare's network.
 */
const BACKEND_ORIGIN = "https://peak-api-production-60b6.up.railway.app";

/** Order placement and wallet deploys are genuinely slow; the backend's own
 *  upstream ceiling is 55s, so stay above it and let it produce the error. */
const BACKEND_TIMEOUT_MS = 60_000;

/**
 * Trading eligibility by region.
 *
 * Polymarket geoblocks restricted regions and rejects their orders outright
 * ("Trading restricted in your region"). Their guidance is for clients to check
 * up front rather than letting a user compose an order that cannot succeed.
 *
 * We resolve the country here, not on the API backend, because the backend only
 * ever sees its own datacenter IP — never the user's. Cloudflare terminates the
 * user's connection, so `request.cf.country` is the real client country.
 *
 * The lists below are a point-in-time snapshot (July 2026) and WILL drift as
 * regulators move; treat CLOB's own rejection as the authority and this as an
 * early, friendlier signal. Unknown country => treated as allowed, because the
 * order is still checked server-side and we would rather not block real users
 * on a missing header.
 */
const REGION_BLOCKED = new Set([
  "US", // CFTC settlement
  "IN", // Online Gaming Rules 2026 — prediction markets prohibited
  "FR",
  "BE",
  "PT",
  "AR",
  "BR",
  "ID",
  "ES",
  // OFAC-sanctioned
  "CU",
  "IR",
  "KP",
  "SY",
  "RU",
  "BY",
]);

/** Existing positions may be closed, but no new ones opened. */
const REGION_CLOSE_ONLY = new Set(["SG", "PL", "TH", "TW"]);

const MAX_QUERY_BYTES = 4096;

/**
 * Upstream deadline. Without this a stalled origin holds the client socket
 * open indefinitely — the phone shows a spinner forever rather than an error
 * it can retry. Comfortably above Gamma's slowest large /events page.
 */
const UPSTREAM_TIMEOUT_MS = 20_000;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

/** First path segment decides the upstream; the rest is forwarded verbatim. */
function resolveTarget(url) {
  const parts = url.pathname.split("/").filter(Boolean);
  if (parts.length < 2) return null;

  const [group, resource, ...rest] = parts;
  const upstream = UPSTREAMS[group];
  const allowed = ROUTES[group];
  if (!upstream || !allowed) return null;
  if (!Object.prototype.hasOwnProperty.call(allowed, resource)) return null;

  // Only ever one extra segment (e.g. /gamma/events/<id>) and it must be a
  // plain id — no traversal, no smuggling a different host into the path.
  if (rest.length > 1) return null;
  if (rest.length === 1 && !/^[A-Za-z0-9._-]{1,128}$/.test(rest[0])) return null;

  const target = new URL(upstream);
  target.pathname = "/" + [resource, ...rest].join("/");
  target.search = url.search;

  return { target, cacheTtl: allowed[resource] };
}

async function handleRest(request, url) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return json({ error: "Method not allowed", code: "method_not_allowed" }, 405);
  }
  if (url.search.length > MAX_QUERY_BYTES) {
    return json({ error: "Query too long", code: "query_too_long" }, 414);
  }

  const resolved = resolveTarget(url);
  if (!resolved) {
    return json({ error: "Not found", code: "not_found" }, 404);
  }
  const { target, cacheTtl } = resolved;

  let upstreamResponse;
  const abort = new AbortController();
  const deadline = setTimeout(() => abort.abort(), UPSTREAM_TIMEOUT_MS);
  try {
    upstreamResponse = await fetch(target.toString(), {
      method: request.method,
      headers: { accept: "application/json" },
      signal: abort.signal,
      // Let Cloudflare collapse concurrent identical requests at the edge.
      cf: cacheTtl > 0 ? { cacheTtl, cacheEverything: true } : { cacheTtl: 0 },
    });
  } catch (err) {
    const timedOut = err?.name === "AbortError";
    return json(
      timedOut
        ? { error: "Upstream timed out", code: "upstream_timeout" }
        : { error: "Upstream unavailable", code: "upstream_unavailable" },
      timedOut ? 504 : 502
    );
  } finally {
    clearTimeout(deadline);
  }

  const headers = new Headers();
  const contentType = upstreamResponse.headers.get("content-type");
  headers.set("content-type", contentType || "application/json; charset=utf-8");
  headers.set(
    "cache-control",
    cacheTtl > 0 ? `public, max-age=${cacheTtl}` : "no-store"
  );
  // Native clients send no Origin; this is only for local browser debugging.
  headers.set("access-control-allow-origin", "*");

  return new Response(upstreamResponse.body, {
    status: upstreamResponse.status,
    headers,
  });
}

/**
 * Transparent WebSocket relay for live CLOB quotes.
 * The client speaks the normal Polymarket market protocol (subscribe with
 * assets_ids, PING every 10s) — this just moves frames across.
 */
async function handleWebSocket(request) {
  // Clients send "websocket", but casing is not guaranteed by the spec and
  // some stacks send "WebSocket" — compare case-insensitively.
  const upgrade = request.headers.get("Upgrade") || "";
  if (upgrade.toLowerCase() !== "websocket") {
    return json({ error: "Expected websocket upgrade", code: "bad_request" }, 426);
  }

  // No AbortSignal here: this fetch is an upgrade handshake, not a normal
  // request/response, and attaching one prevents the 101 from being returned
  // with a usable `webSocket`. Idle handling is the relay's job below.
  let upstreamResponse;
  try {
    upstreamResponse = await fetch(WS_UPSTREAM, {
      headers: { Upgrade: "websocket" },
    });
  } catch (err) {
    return json({ error: "Upstream unavailable", code: "upstream_unavailable" }, 502);
  }

  const upstream = upstreamResponse.webSocket;
  if (!upstream) {
    return json({ error: "Upstream refused websocket", code: "upstream_no_ws" }, 502);
  }

  const pair = new WebSocketPair();
  const [clientSide, serverSide] = Object.values(pair);

  upstream.accept();
  serverSide.accept();

  // Pipe both directions. Either side closing tears down the other so we don't
  // leak a half-open upstream connection per dropped client.
  serverSide.addEventListener("message", (event) => {
    try {
      upstream.send(event.data);
    } catch {
      /* upstream already gone; close below handles teardown */
    }
  });
  upstream.addEventListener("message", (event) => {
    try {
      serverSide.send(event.data);
    } catch {
      /* client already gone */
    }
  });

  const closeBoth = (code, reason) => {
    try {
      upstream.close(code, reason);
    } catch {}
    try {
      serverSide.close(code, reason);
    } catch {}
  };

  // 1000-range codes are the only ones safe to forward verbatim.
  serverSide.addEventListener("close", (e) => closeBoth(1000, e.reason || ""));
  upstream.addEventListener("close", (e) => closeBoth(1000, e.reason || ""));
  serverSide.addEventListener("error", () => closeBoth(1011, "client error"));
  upstream.addEventListener("error", () => closeBoth(1011, "upstream error"));

  return new Response(null, { status: 101, webSocket: clientSide });
}

/**
 * Reverse proxy for Peak's own backend. Unlike the Polymarket routes this
 * forwards every path and method verbatim — it fronts a single origin we
 * control, so it is not an open proxy, and the backend still enforces its own
 * Privy/APP_TOKEN auth. Auth headers pass straight through.
 */
async function handleBackend(request, url, env) {
  const target = new URL(url.pathname + url.search, BACKEND_ORIGIN);

  const headers = new Headers(request.headers);
  // Let fetch set Host from the target; a stale Host makes Railway 404.
  headers.delete("host");

  // Tell the backend the user's real country. It cannot work this out itself —
  // it only ever sees this Worker's IP — and a client-side check alone is
  // cosmetic. Delete first: these are attacker-controlled until we overwrite
  // them, and the whole point is that the client cannot choose its own region.
  headers.delete("x-peak-country");
  headers.delete("x-peak-region-status");
  headers.delete("x-peak-edge-secret");

  // Proves the request came through here, so the backend can refuse direct
  // origin calls that would otherwise skip the region gate. Deleted first: a
  // client must never be able to supply its own.
  if (env?.PEAK_EDGE_SECRET) {
    headers.set("x-peak-edge-secret", env.PEAK_EDGE_SECRET);
  }
  const country = request.cf?.country ?? null;
  if (country) {
    const blocked = REGION_BLOCKED.has(country);
    const closeOnly = REGION_CLOSE_ONLY.has(country);
    headers.set("x-peak-country", country);
    headers.set("x-peak-region-status", blocked ? "blocked" : closeOnly ? "close_only" : "allowed");
  }

  const hasBody = request.method !== "GET" && request.method !== "HEAD";
  const abort = new AbortController();
  const deadline = setTimeout(() => abort.abort(), BACKEND_TIMEOUT_MS);
  try {
    const upstream = await fetch(target.toString(), {
      method: request.method,
      headers,
      body: hasBody ? await request.arrayBuffer() : undefined,
      signal: abort.signal,
      redirect: "manual",
    });

    const out = new Headers(upstream.headers);
    // Never let an authenticated trading response sit in a shared cache.
    out.set("cache-control", "no-store");
    return new Response(upstream.body, { status: upstream.status, headers: out });
  } catch (err) {
    const timedOut = err?.name === "AbortError";
    return json(
      timedOut
        ? { error: "Upstream timed out", code: "upstream_timeout" }
        : { error: "Upstream unavailable", code: "upstream_unavailable" },
      timedOut ? 504 : 502
    );
  } finally {
    clearTimeout(deadline);
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // api.<domain> fronts the Peak backend; edge.<domain> fronts Polymarket.
    if (url.hostname.startsWith("api.")) {
      return handleBackend(request, url, env);
    }

    if (url.pathname === "/health") {
      return json({ ok: true, service: "peak-edge" });
    }

    if (url.pathname === "/geo") {
      const country = request.cf?.country ?? null;
      const blocked = country != null && REGION_BLOCKED.has(country);
      const closeOnly = country != null && REGION_CLOSE_ONLY.has(country);
      return new Response(
        JSON.stringify({
          country,
          canTrade: !blocked && !closeOnly,
          canClose: !blocked,
          status: blocked ? "blocked" : closeOnly ? "close_only" : "allowed",
        }),
        {
          headers: {
            "content-type": "application/json; charset=utf-8",
            // Per-user answer — must never be shared between viewers.
            "cache-control": "no-store",
          },
        }
      );
    }
    if (url.pathname === "/ws/market") {
      return handleWebSocket(request);
    }
    return handleRest(request, url);
  },
};
