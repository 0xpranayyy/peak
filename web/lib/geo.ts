/**
 * Optional browser geo hint via the public edge Worker.
 *
 * Unknown / unreachable geo is treated as allowed for UI purposes. Real
 * enforcement is Worker → API region headers + CLOB on submit — not a page
 * banner. Matches backend `shouldRefuseForRegion` (unknown = allow).
 */

const EDGE = process.env.NEXT_PUBLIC_PEAK_EDGE_URL ?? "https://edge.peakapp.site";

export type GeoStatus = {
  country: string | null;
  canTrade: boolean;
  canClose: boolean;
  status: "allowed" | "blocked" | "close_only" | "unknown";
};

const UNKNOWN_OPEN: GeoStatus = {
  country: null,
  canTrade: true,
  canClose: true,
  status: "unknown",
};

export async function fetchGeo(): Promise<GeoStatus> {
  try {
    // Every other call in this client carries a deadline; this one did not, so
    // a hung edge left `geo` null for the whole session instead of falling back
    // to the open default.
    const response = await fetch(`${EDGE}/geo`, {
      cache: "no-store",
      headers: { accept: "application/json" },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) return UNKNOWN_OPEN;
    const json = (await response.json()) as Record<string, unknown>;
    const statusRaw = String(json.status || "unknown");
    const status =
      statusRaw === "blocked" || statusRaw === "close_only" || statusRaw === "allowed"
        ? statusRaw
        : "unknown";
    if (status === "unknown") return UNKNOWN_OPEN;
    return {
      country: typeof json.country === "string" ? json.country : null,
      canTrade: status === "allowed" && json.canTrade !== false,
      canClose: json.canClose !== false && status !== "blocked",
      status,
    };
  } catch {
    return UNKNOWN_OPEN;
  }
}
