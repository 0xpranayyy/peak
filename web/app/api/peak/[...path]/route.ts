/**
 * Same-origin proxy to the Peak trading API (legacy fallback).
 *
 * Prefer browser → `api.peakapp.site` (Worker CORS + path allowlist). Pages
 * Functions intermittently return raw Cloudflare `error code: 502` under load
 * when proxying here, which blocked sign-in. Kept for older bundles / SSR
 * helpers that still hit `/api/peak/*`.
 *
 * Browser → /api/peak/* → api.peakapp.site → Railway
 *
 * Geo caveat: the Worker would otherwise stamp `x-peak-country` from *this*
 * Pages fetch (colo IP), not the trader. When `PEAK_WEB_PROXY_SECRET` matches
 * the Worker secret, we forward the browser's CF country as
 * `x-peak-client-country` so the region gate stays honest.
 *
 * Path allowlist: only routes the web client needs. Blocks key-handling
 * endpoints (`/auth/resolve-secret`, `/auth/sign-siwe`, `/auth/import-wallet`)
 * from the app origin even if XSS ever lands here.
 */

export const runtime = "edge";

const UPSTREAM = process.env.PEAK_API_URL ?? "https://api.peakapp.site";
const WEB_PROXY_SECRET = process.env.PEAK_WEB_PROXY_SECRET ?? "";

const HOP_BY_HOP = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailers",
  "transfer-encoding",
  "upgrade",
  "host",
  "content-length",
]);

/** Exact paths + order-id cancel. Methods enforced per route. */
const ALLOWED: { pattern: RegExp; methods: ReadonlySet<string> }[] = [
  { pattern: /^health$/, methods: new Set(["GET", "HEAD"]) },
  { pattern: /^auth\/session$/, methods: new Set(["POST"]) },
  { pattern: /^trading\/setup$/, methods: new Set(["POST"]) },
  { pattern: /^portfolio$/, methods: new Set(["GET", "HEAD"]) },
  { pattern: /^activity$/, methods: new Set(["GET", "HEAD"]) },
  { pattern: /^orders$/, methods: new Set(["GET", "HEAD", "POST"]) },
  { pattern: /^orders\/prepare$/, methods: new Set(["POST"]) },
  { pattern: /^orders\/[^/]+$/, methods: new Set(["DELETE"]) },
  { pattern: /^deposit-address$/, methods: new Set(["POST"]) },
];

type Ctx = { params: Promise<{ path: string[] }> };

function clientCountry(request: Request): string | null {
  const cf = (request as Request & { cf?: { country?: string } }).cf;
  if (cf?.country && /^[A-Z]{2}$/i.test(cf.country)) {
    return cf.country.toUpperCase();
  }
  const header = request.headers.get("cf-ipcountry");
  if (header && header !== "XX" && /^[A-Z]{2}$/i.test(header)) {
    return header.toUpperCase();
  }
  return null;
}

function isAllowedPath(joined: string, method: string): boolean {
  for (const rule of ALLOWED) {
    if (rule.pattern.test(joined) && rule.methods.has(method)) return true;
  }
  return false;
}

function upstreamLooksUnsafe(url: string): boolean {
  try {
    const host = new URL(url).hostname.toLowerCase();
    // Region / edge-secret gates live on the Worker in front of api.peakapp.site.
    // Hitting Railway origin directly skips those stamps.
    return host.endsWith(".up.railway.app") || host.endsWith(".railway.app");
  } catch {
    return true;
  }
}

async function forward(request: Request, ctx: Ctx): Promise<Response> {
  const { path } = await ctx.params;
  if (!path?.length) {
    return Response.json({ error: "Missing path" }, { status: 400 });
  }

  const joined = path.map(encodeURIComponent).join("/");
  const method = request.method.toUpperCase();

  if (!isAllowedPath(joined, method)) {
    return Response.json(
      { error: "Not found", code: "proxy_path_denied" },
      { status: 404 }
    );
  }

  if (upstreamLooksUnsafe(UPSTREAM)) {
    return Response.json(
      {
        error:
          "PEAK_API_URL must point at the Worker-fronted API host (api.peakapp.site), not Railway origin.",
        code: "upstream_misconfigured",
      },
      { status: 500 }
    );
  }

  const incoming = new URL(request.url);
  const target = new URL(joined, `${UPSTREAM.replace(/\/$/, "")}/`);
  target.search = incoming.search;

  const headers = new Headers();
  for (const [key, value] of request.headers.entries()) {
    if (HOP_BY_HOP.has(key.toLowerCase())) continue;
    // Drop browser Origin so upstream CORS middleware does not reject us.
    if (key.toLowerCase() === "origin") continue;
    // Never let the browser spoof region / proxy claims — we set those below.
    if (
      key.toLowerCase() === "x-peak-client-country" ||
      key.toLowerCase() === "x-peak-web-proxy-secret" ||
      key.toLowerCase() === "x-peak-country" ||
      key.toLowerCase() === "x-peak-region-status" ||
      key.toLowerCase() === "x-peak-edge-secret"
    ) {
      continue;
    }
    headers.set(key, value);
  }
  headers.set("accept", "application/json");

  const country = clientCountry(request);
  if (WEB_PROXY_SECRET && country) {
    headers.set("x-peak-client-country", country);
    headers.set("x-peak-web-proxy-secret", WEB_PROXY_SECRET);
  }

  const hasBody = method !== "GET" && method !== "HEAD";

  let upstream: Response;
  try {
    upstream = await fetch(target.toString(), {
      method,
      headers,
      body: hasBody ? await request.arrayBuffer() : undefined,
      redirect: "manual",
    });
  } catch {
    return Response.json(
      { error: "Peak API unavailable", code: "upstream_unavailable" },
      { status: 502 }
    );
  }

  const out = new Headers(upstream.headers);
  out.set("cache-control", "no-store");
  // Strip upstream CORS — response is same-origin to the web app.
  out.delete("access-control-allow-origin");
  out.delete("access-control-allow-credentials");
  out.delete("access-control-allow-headers");
  out.delete("access-control-allow-methods");

  return new Response(upstream.body, { status: upstream.status, headers: out });
}

export const GET = forward;
export const POST = forward;
export const PUT = forward;
export const PATCH = forward;
export const DELETE = forward;
export const HEAD = forward;

export async function OPTIONS() {
  return new Response(null, { status: 204 });
}
