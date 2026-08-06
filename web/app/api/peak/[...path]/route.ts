/**
 * Same-origin proxy to the Peak trading API.
 *
 * Browser → /api/peak/* → api.peakapp.site
 *
 * Why not call the API from the browser? Railway CORS is intentionally off for
 * the iOS-only default (`CORS_ORIGINS` empty). Proxying keeps the web client
 * working without widening the API allow-list, and still hits the Worker-fronted
 * `api.peakapp.site` host so region headers / edge secret stay intact.
 */

export const runtime = "edge";

const UPSTREAM = process.env.PEAK_API_URL ?? "https://api.peakapp.site";

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

type Ctx = { params: Promise<{ path: string[] }> };

async function forward(request: Request, ctx: Ctx): Promise<Response> {
  const { path } = await ctx.params;
  if (!path?.length) {
    return Response.json({ error: "Missing path" }, { status: 400 });
  }

  const incoming = new URL(request.url);
  const target = new URL(path.map(encodeURIComponent).join("/"), `${UPSTREAM}/`);
  target.search = incoming.search;

  const headers = new Headers();
  for (const [key, value] of request.headers.entries()) {
    if (HOP_BY_HOP.has(key.toLowerCase())) continue;
    // Drop browser Origin so upstream CORS middleware does not reject us.
    if (key.toLowerCase() === "origin") continue;
    headers.set(key, value);
  }
  headers.set("accept", "application/json");

  const method = request.method.toUpperCase();
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
