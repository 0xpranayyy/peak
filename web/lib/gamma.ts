/**
 * Read-only Gamma client for market browsing.
 *
 * Everything here goes through the existing Cloudflare Worker at
 * `edge.peakapp.site`, the same host iOS uses. Two reasons that matters:
 *
 *  1. Indian ISPs block `*.polymarket.com` at the TLS layer, so the browser must
 *     never send that SNI either — see worker/README.md.
 *  2. The Worker already returns `access-control-allow-origin: *` and only
 *     serves public, path-allowlisted, credential-free reads, so a browser can
 *     call it with no infrastructure changes.
 *
 * Authenticated trading talks to `api.peakapp.site` directly (Worker CORS).
 */

const EDGE = process.env.NEXT_PUBLIC_PEAK_EDGE_URL ?? "https://edge.peakapp.site";

// ---------------------------------------------------------------- raw shapes

/**
 * Gamma is inconsistent about types: numbers arrive as numbers *or* numeric
 * strings, and `outcomes` / `outcomePrices` / `clobTokenIds` arrive as JSON
 * strings containing an array — e.g. the literal `"[\"Yes\", \"No\"]"`, not an
 * array. The iOS client carries `FlexibleDouble` / `FlexibleStringArray` for
 * exactly this; these two helpers are the TypeScript equivalent.
 */
function flexNumber(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function flexStringArray(value: unknown): string[] {
  if (Array.isArray(value)) return value.map(String);
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) return parsed.map(String);
    } catch {
      // Not JSON — fall through and treat as empty rather than throwing on a
      // single malformed row and losing the whole page.
    }
  }
  return [];
}

// ------------------------------------------------------------------- domain

export interface Market {
  id: string;
  question: string;
  /**
   * Gamma's `groupItemTitle` — the short leg name inside a multi-market event
   * ("August 31", "Match Winner"). `question` repeats the whole event title on
   * every leg, so this is the only label short enough to put in a list row.
   */
  shortTitle: string | null;
  slug: string | null;
  outcomes: string[];
  /** Aligned with `outcomes`, 0...1. */
  outcomePrices: number[];
  volume: number;
  volume24hr: number;
  liquidity: number;
  endDate: string | null;
  active: boolean;
  closed: boolean;
  imageUrl: string | null;
  /** Probability of the Yes-like outcome, or null when Gamma has not priced it. */
  yesPrice: number | null;
  /** CLOB token ids aligned with `outcomes` — required to place orders. */
  clobTokenIds: string[];
  negRisk: boolean;
}

export interface PeakEvent {
  id: string;
  slug: string | null;
  title: string;
  description: string | null;
  imageUrl: string | null;
  endDate: string | null;
  volume: number;
  volume24hr: number;
  liquidity: number;
  tags: { id: string; label: string; slug: string | null }[];
  markets: Market[];
  /** Headline probability for the card — the first market's Yes price. */
  displayProbability: number | null;
}

/**
 * The headline number for an event row.
 *
 * A binary event has one obvious answer — its Yes price. A multi-market event
 * does not, and showing a bare leg count ("28 markets") tells a scanner nothing
 * about the event. So rank the legs by price and surface the leader, captioned
 * with that leg's own short name. Gamma's leg order is arbitrary, so the ranking
 * matters: `displayProbability` alone would show whichever leg happened to be
 * first.
 */
export function headlineOdds(event: PeakEvent): {
  probability: number | null;
  caption: string;
} {
  if (event.markets.length <= 1) {
    return { probability: event.displayProbability, caption: "chance" };
  }

  let leader: Market | null = null;
  for (const market of event.markets) {
    if (market.yesPrice === null) continue;
    if (leader === null || market.yesPrice > (leader.yesPrice ?? 0)) leader = market;
  }

  return {
    probability: leader?.yesPrice ?? null,
    caption: leader?.shortTitle ?? `${event.markets.length} markets`,
  };
}

// ------------------------------------------------------------------ mapping

function mapMarket(raw: Record<string, unknown>): Market | null {
  const id = raw.id != null ? String(raw.id) : null;
  const question = typeof raw.question === "string" ? raw.question : null;
  if (!id || !question) return null;

  const outcomes = flexStringArray(raw.outcomes);
  const prices = flexStringArray(raw.outcomePrices)
    .map((p) => Number(p))
    .filter((p) => Number.isFinite(p));

  const resolvedOutcomes = outcomes.length > 0 ? outcomes : ["Yes", "No"];
  const resolvedPrices = prices.length > 0 ? prices : [];

  // Prefer an explicit "Yes"; otherwise the first slot, matching iOS.
  const yesIndex = resolvedOutcomes.findIndex(
    (o) => o.toLowerCase() === "yes"
  );
  const priceIndex = yesIndex >= 0 ? yesIndex : 0;
  const rawYes = resolvedPrices[priceIndex];
  const yesPrice =
    typeof rawYes === "number" && rawYes > 0 && rawYes <= 1 ? rawYes : null;

  const archived = raw.archived === true;
  const clobTokenIds = flexStringArray(raw.clobTokenIds);

  return {
    id,
    question,
    shortTitle:
      typeof raw.groupItemTitle === "string" && raw.groupItemTitle.trim()
        ? raw.groupItemTitle.trim()
        : null,
    slug: typeof raw.slug === "string" ? raw.slug : null,
    outcomes: resolvedOutcomes,
    outcomePrices: resolvedPrices,
    volume: flexNumber(raw.volume) ?? flexNumber(raw.volumeNum) ?? 0,
    volume24hr: flexNumber(raw.volume24hr) ?? 0,
    liquidity: flexNumber(raw.liquidity) ?? flexNumber(raw.liquidityNum) ?? 0,
    endDate: typeof raw.endDate === "string" ? raw.endDate : null,
    active: archived ? false : raw.active !== false,
    closed: archived ? true : raw.closed === true,
    imageUrl:
      (typeof raw.image === "string" && raw.image) ||
      (typeof raw.icon === "string" && raw.icon) ||
      null,
    yesPrice,
    clobTokenIds,
    negRisk: raw.negRisk === true,
  };
}

function mapEvent(raw: Record<string, unknown>): PeakEvent | null {
  const id = raw.id != null ? String(raw.id) : null;
  const title = typeof raw.title === "string" ? raw.title : null;
  if (!id || !title) return null;

  const markets = Array.isArray(raw.markets)
    ? (raw.markets as Record<string, unknown>[])
        .map(mapMarket)
        .filter((m): m is Market => m !== null)
    : [];

  if (markets.length === 0) return null;

  const tags = Array.isArray(raw.tags)
    ? (raw.tags as Record<string, unknown>[])
        .map((t) => {
          const label =
            (typeof t.label === "string" && t.label) ||
            (typeof t.name === "string" && t.name) ||
            (typeof t.slug === "string" && t.slug) ||
            null;
          const tagId =
            (t.id != null && String(t.id)) ||
            (typeof t.slug === "string" && t.slug) ||
            label;
          if (!label || !tagId) return null;
          return {
            id: String(tagId),
            label,
            slug: typeof t.slug === "string" ? t.slug : null,
          };
        })
        .filter((t): t is { id: string; label: string; slug: string | null } => t !== null)
    : [];

  return {
    id,
    slug: typeof raw.slug === "string" ? raw.slug : null,
    title,
    description: typeof raw.description === "string" ? raw.description : null,
    imageUrl:
      (typeof raw.image === "string" && raw.image) ||
      (typeof raw.icon === "string" && raw.icon) ||
      null,
    endDate: typeof raw.endDate === "string" ? raw.endDate : null,
    volume: flexNumber(raw.volume) ?? 0,
    volume24hr: flexNumber(raw.volume24hr) ?? 0,
    liquidity: flexNumber(raw.liquidity) ?? 0,
    tags,
    markets,
    displayProbability: markets[0]?.yesPrice ?? null,
  };
}

/** Event-level filters Gamma applies loosely — mirrors `isListEligible` on iOS. */
function isListEligible(raw: Record<string, unknown>): boolean {
  if (raw.archived === true) return false;
  if (raw.closed === true) return false;
  if (raw.active === false) return false;
  // Gamma often leaves sports events `active` hours after tip-off with a past
  // endDate. Those dominate volume24hr and open into a dead trade ticket.
  if (typeof raw.endDate === "string" && raw.endDate.trim()) {
    const end = Date.parse(raw.endDate);
    if (Number.isFinite(end) && end < Date.now() - 30 * 60_000) return false;
  }
  return true;
}

// ----------------------------------------------------------------- requests

async function getGamma<T>(
  path: string,
  query: Record<string, string | number | undefined>,
  _revalidate: number
): Promise<T> {
  const url = new URL(`${EDGE}/gamma/${path}`);
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined) url.searchParams.set(key, String(value));
  }

  // Always `cache: "no-store"` here. Cloudflare Pages Functions mishandle
  // Next’s `next.revalidate` Cache API on large Gamma payloads (multi‑MB
  // `/events` lists), and the Worker already applies its own edge TTL.
  // Event-detail SSR stays small (`?slug=` / `/events/:id`).
  const response = await fetch(url.toString(), {
    cache: "no-store",
    headers: { accept: "application/json" },
    signal: AbortSignal.timeout(20_000),
  });

  if (!response.ok) {
    throw new Error(`Gamma ${path} failed: ${response.status}`);
  }
  return (await response.json()) as T;
}

const SHOWCASE = { active: "true", closed: "false", archived: "false" } as const;

export type SortKey = "volume24hr" | "volume" | "liquidity" | "endDate";

/** Default browse sort — all-time volume surfaces markets with live books. */
export const DEFAULT_SORT: SortKey = "volume24hr";

/** Paginated live events for the browse feed. */
export async function fetchEvents(options?: {
  limit?: number;
  offset?: number;
  sort?: SortKey;
  tagSlug?: string;
}): Promise<PeakEvent[]> {
  const raw = await getGamma<Record<string, unknown>[]>(
    "events",
    {
      limit: options?.limit ?? 24,
      offset: options?.offset ?? 0,
      order: options?.sort ?? DEFAULT_SORT,
      ascending: "false",
      tag_slug: options?.tagSlug,
      ...SHOWCASE,
    },
    60
  );

  if (!Array.isArray(raw)) return [];
  return raw
    .filter(isListEligible)
    .map(mapEvent)
    .filter((e): e is PeakEvent => e !== null);
}

export interface Tag {
  id: string;
  label: string;
  slug: string;
}

/** Category chips for the feed. Only tags with a slug are usable as filters. */
export async function fetchTags(limit = 30): Promise<Tag[]> {
  const raw = await getGamma<Record<string, unknown>[]>(
    "tags",
    { limit, offset: 0 },
    600
  );
  if (!Array.isArray(raw)) return [];

  const seen = new Set<string>();
  const tags: Tag[] = [];
  for (const t of raw) {
    const slug = typeof t.slug === "string" ? t.slug : null;
    const label =
      (typeof t.label === "string" && t.label) ||
      (typeof t.name === "string" && t.name) ||
      slug;
    if (!slug || !label || seen.has(slug)) continue;
    seen.add(slug);
    tags.push({ id: String(t.id ?? slug), label, slug });
  }
  return tags;
}

/** Full-text search across live events. */
export async function searchEvents(query: string, limit = 24): Promise<PeakEvent[]> {
  const trimmed = query.trim();
  if (!trimmed) return [];

  const raw = await getGamma<Record<string, unknown> | Record<string, unknown>[]>(
    "public-search",
    { q: trimmed, limit_per_type: limit, events_status: "active" },
    30
  );

  // public-search returns an object keyed by type, unlike the list endpoints.
  const events = Array.isArray(raw)
    ? raw
    : Array.isArray((raw as Record<string, unknown>)?.events)
      ? ((raw as Record<string, unknown>).events as Record<string, unknown>[])
      : [];

  return events
    .filter(isListEligible)
    .map(mapEvent)
    .filter((e): e is PeakEvent => e !== null);
}

/**
 * One event by slug, for the detail page.
 *
 * Detail deliberately does not apply the showcase filters — a link to a closed
 * or resolved market should still render rather than 404, which also keeps
 * previously indexed URLs alive.
 *
 * Called from the browser (EventClient). Do not wrap in React `cache()` —
 * that is server-only and this module is shared with client components.
 */
export async function fetchEventBySlug(slug: string): Promise<PeakEvent | null> {
  const raw = await getGamma<Record<string, unknown>[]>(
    "events",
    { slug, limit: 1 },
    30
  );
  if (!Array.isArray(raw) || raw.length === 0) return null;
  return mapEvent(raw[0]);
}

/** One event by Gamma id — used by the local watchlist. */
export async function fetchEventById(id: string): Promise<PeakEvent | null> {
  const trimmed = id.trim();
  if (!trimmed) return null;
  const url = new URL(`${EDGE}/gamma/events/${encodeURIComponent(trimmed)}`);
  const response = await fetch(url.toString(), {
    headers: { accept: "application/json" },
    cache: "no-store",
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) return null;
  const raw = (await response.json()) as Record<string, unknown>;
  return mapEvent(raw);
}
