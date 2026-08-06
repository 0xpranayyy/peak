/** Browser geo check via the public edge Worker. */

const EDGE = process.env.NEXT_PUBLIC_PEAK_EDGE_URL ?? "https://edge.peakapp.site";

export type GeoStatus = {
  country: string | null;
  canTrade: boolean;
  canClose: boolean;
  status: "allowed" | "blocked" | "close_only" | "unknown";
};

export async function fetchGeo(): Promise<GeoStatus> {
  try {
    const response = await fetch(`${EDGE}/geo`, {
      cache: "no-store",
      headers: { accept: "application/json" },
    });
    if (!response.ok) {
      // Fail closed for new buys when /geo is unreachable; sells stay open
      // until backend/CLOB refuse — matches close-only posture.
      return { country: null, canTrade: false, canClose: true, status: "unknown" };
    }
    const json = (await response.json()) as Record<string, unknown>;
    const statusRaw = String(json.status || "unknown");
    const status =
      statusRaw === "blocked" || statusRaw === "close_only" || statusRaw === "allowed"
        ? statusRaw
        : "unknown";
    return {
      country: typeof json.country === "string" ? json.country : null,
      canTrade:
        status === "allowed" &&
        json.canTrade !== false,
      canClose: json.canClose !== false && status !== "blocked",
      status,
    };
  } catch {
    return { country: null, canTrade: false, canClose: true, status: "unknown" };
  }
}
