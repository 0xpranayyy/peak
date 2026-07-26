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
};

const WS_UPSTREAM = "wss://ws-subscriptions-clob.polymarket.com/ws/market";

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
};

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
  if (request.headers.get("Upgrade") !== "websocket") {
    return json({ error: "Expected websocket upgrade", code: "bad_request" }, 426);
  }

  let upstreamResponse;
  const abort = new AbortController();
  const deadline = setTimeout(() => abort.abort(), UPSTREAM_TIMEOUT_MS);
  try {
    upstreamResponse = await fetch(WS_UPSTREAM, {
      headers: { Upgrade: "websocket" },
      signal: abort.signal,
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

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({ ok: true, service: "peak-edge" });
    }
    if (url.pathname === "/ws/market") {
      return handleWebSocket(request);
    }
    return handleRest(request, url);
  },
};
