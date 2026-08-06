/**
 * Public CLOB reads via the Peak edge Worker (never SNI to polymarket.com).
 * Book + prices-history match iOS `CLOBAPI` / EventDetail.
 */

const EDGE = process.env.NEXT_PUBLIC_PEAK_EDGE_URL ?? "https://edge.peakapp.site";

export type TopOfBook = {
  bid: number | null;
  ask: number | null;
  mid: number | null;
  spread: number | null;
};

export type BookLevel = {
  price: number;
  size: number;
};

export type OrderBook = {
  bids: BookLevel[];
  asks: BookLevel[];
  bid: number | null;
  ask: number | null;
  mid: number | null;
  spread: number | null;
};

export type PricePoint = {
  t: number;
  p: number;
};

/** Intervals accepted by CLOB `/prices-history` — same as iOS. */
export type HistoryInterval = "1h" | "6h" | "1d" | "1w" | "1m" | "max";

export const HISTORY_INTERVALS: {
  key: HistoryInterval;
  label: string;
  fidelity: number;
}[] = [
  { key: "1h", label: "1H", fidelity: 1 },
  { key: "6h", label: "6H", fidelity: 5 },
  { key: "1d", label: "1D", fidelity: 15 },
  { key: "1w", label: "1W", fidelity: 60 },
  { key: "1m", label: "1M", fidelity: 240 },
  { key: "max", label: "ALL", fidelity: 720 },
];

const BOOK_DEPTH = 12;

function num(value: unknown): number | null {
  const n = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
  return Number.isFinite(n) ? n : null;
}

function price01(value: unknown): number | null {
  const n = num(value);
  return n != null && n > 0 && n < 1 ? n : null;
}

function parseLevels(raw: unknown): BookLevel[] {
  if (!Array.isArray(raw)) return [];
  const levels: BookLevel[] = [];
  for (const row of raw) {
    if (!row || typeof row !== "object") continue;
    const r = row as Record<string, unknown>;
    const price = price01(r.price);
    const size = num(r.size);
    if (price == null || size == null || size <= 0) continue;
    levels.push({ price, size });
  }
  return levels;
}

function summarize(bids: BookLevel[], asks: BookLevel[]): TopOfBook {
  const bid = bids.length ? bids[0].price : null;
  const ask = asks.length ? asks[0].price : null;
  const mid =
    bid != null && ask != null ? Math.round(((bid + ask) / 2) * 1000) / 1000 : null;
  const spread =
    bid != null && ask != null ? Math.round((ask - bid) * 1000) / 1000 : null;
  return { bid, ask, mid, spread };
}

/** Full depth book for a token. Empty levels on failure — never mock. */
export async function fetchOrderBook(tokenID: string): Promise<OrderBook> {
  const empty: OrderBook = {
    bids: [],
    asks: [],
    bid: null,
    ask: null,
    mid: null,
    spread: null,
  };
  try {
    const url = new URL(`${EDGE}/clob/book`);
    url.searchParams.set("token_id", tokenID);
    const response = await fetch(url.toString(), {
      cache: "no-store",
      headers: { accept: "application/json" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) return empty;

    const json = (await response.json()) as Record<string, unknown>;
    const bids = parseLevels(json.bids).sort((a, b) => b.price - a.price);
    const asks = parseLevels(json.asks).sort((a, b) => a.price - b.price);
    const top = summarize(bids, asks);
    return {
      bids: bids.slice(0, BOOK_DEPTH),
      asks: asks.slice(0, BOOK_DEPTH),
      ...top,
    };
  } catch {
    return empty;
  }
}

/** Best bid / ask for a token. Failures return nulls — ticket still works. */
export async function fetchTopOfBook(tokenID: string): Promise<TopOfBook> {
  const book = await fetchOrderBook(tokenID);
  return {
    bid: book.bid,
    ask: book.ask,
    mid: book.mid,
    spread: book.spread,
  };
}

/**
 * Midpoint price history from CLOB `/prices-history`.
 * Real series only — empty array when none / error.
 */
export async function fetchPriceHistory(
  tokenID: string,
  interval: HistoryInterval = "1d",
  fidelity?: number
): Promise<PricePoint[]> {
  try {
    const meta = HISTORY_INTERVALS.find((i) => i.key === interval);
    const url = new URL(`${EDGE}/clob/prices-history`);
    url.searchParams.set("market", tokenID);
    url.searchParams.set("interval", interval);
    url.searchParams.set(
      "fidelity",
      String(fidelity ?? meta?.fidelity ?? 60)
    );
    const response = await fetch(url.toString(), {
      cache: "no-store",
      headers: { accept: "application/json" },
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) return [];

    const json = (await response.json()) as Record<string, unknown>;
    const history = Array.isArray(json.history) ? json.history : [];
    const points: PricePoint[] = [];
    for (const row of history) {
      if (!row || typeof row !== "object") continue;
      const r = row as Record<string, unknown>;
      const t = num(r.t);
      const p = num(r.p);
      if (t == null || p == null || p < 0 || p > 1) continue;
      points.push({ t, p });
    }
    // Cap for chart performance (iOS uses 360).
    if (points.length > 480) {
      const step = Math.ceil(points.length / 480);
      return points.filter((_, i) => i % step === 0 || i === points.length - 1);
    }
    return points;
  } catch {
    return [];
  }
}
