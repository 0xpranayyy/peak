/**
 * Public CLOB reads via the Peak edge Worker (never SNI to polymarket.com).
 */

const EDGE = process.env.NEXT_PUBLIC_PEAK_EDGE_URL ?? "https://edge.peakapp.site";

export type TopOfBook = {
  bid: number | null;
  ask: number | null;
  mid: number | null;
  spread: number | null;
};

function num(value: unknown): number | null {
  const n = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
  return Number.isFinite(n) && n > 0 && n < 1 ? n : null;
}

/** Best bid / ask for a token. Failures return nulls — ticket still works. */
export async function fetchTopOfBook(tokenID: string): Promise<TopOfBook> {
  try {
    const url = new URL(`${EDGE}/clob/book`);
    url.searchParams.set("token_id", tokenID);
    const response = await fetch(url.toString(), {
      cache: "no-store",
      headers: { accept: "application/json" },
    });
    if (!response.ok) {
      return { bid: null, ask: null, mid: null, spread: null };
    }
    const json = (await response.json()) as Record<string, unknown>;
    const bids = Array.isArray(json.bids) ? json.bids : [];
    const asks = Array.isArray(json.asks) ? json.asks : [];
    const bestBid = bids[0] as Record<string, unknown> | undefined;
    const bestAsk = asks[0] as Record<string, unknown> | undefined;
    const bid = num(bestBid?.price);
    const ask = num(bestAsk?.price);
    const mid = bid != null && ask != null ? Math.round(((bid + ask) / 2) * 1000) / 1000 : null;
    const spread =
      bid != null && ask != null ? Math.round((ask - bid) * 1000) / 1000 : null;
    return { bid, ask, mid, spread };
  } catch {
    return { bid: null, ask: null, mid: null, spread: null };
  }
}
