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
 * does not, and a bare leg count ("28 markets") tells a scanner nothing. So pick
 * one leg and caption it with that leg's own short name. Gamma's leg order is
 * arbitrary, so the choice matters: `displayProbability` alone shows whichever
 * leg happened to be listed first.
 *
 * The rule: **the cheapest leg the market still favours** — the lowest price at
 * or above 50% — falling back to the most-favoured leg when the market favours
 * nothing at all.
 *
 * Highest price alone is wrong, because many events are ladders rather than a
 * field of rivals. "Bitcoin above ___ on August 7" lists a strike per level and
 * every strike under spot sits at 100%, so a page of them renders as a wall of
 * identical 100%s. The cheapest favoured leg is the strike nearest the money —
 * the one number on the row that tells you where Bitcoin actually is.
 *
 * It also reads correctly at both extremes:
 *
 *  - A field of rivals (Fed decision: 1¢, 2¢, 49¢, 49¢, 1¢) favours nothing, so
 *    the fallback gives the front-runner, 49%.
 *  - A ladder that has already resolved is all 100s and 0s; the cheapest
 *    favoured leg is the boundary strike, so the row says "above 64,000 · 100%"
 *    — where the price ended up — rather than "above 66,000 · 0%".
 *
 * This selects among real legs and shows each one's real price against its own
 * name. It never blends, rounds toward a story, or invents a number.
 */
export function headlineOdds(event: PeakEvent): {
  probability: number | null;
  caption: string;
} {
  if (event.markets.length <= 1) {
    return { probability: event.displayProbability, caption: "chance" };
  }

  let cheapestFavoured: Market | null = null;
  let mostFavoured: Market | null = null;

  for (const market of event.markets) {
    const price = market.yesPrice;
    if (price === null) continue;

    if (mostFavoured === null || price > (mostFavoured.yesPrice ?? -1)) {
      mostFavoured = market;
    }
    // `<=`, not `<`: a resolved ladder has several legs pegged at exactly 100%,
    // and Gamma lists them in ladder order, so the last of the tied ones is the
    // boundary strike — "above 64,000" rather than "above 52,000".
    if (
      price >= 0.5 &&
      (cheapestFavoured === null || price <= (cheapestFavoured.yesPrice ?? 2))
    ) {
      cheapestFavoured = market;
    }
  }

  const pick = cheapestFavoured ?? mostFavoured;
  return {
    probability: pick?.yesPrice ?? null,
    caption: pick?.shortTitle ?? `${event.markets.length} markets`,
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

/**
 * A signal that aborts when the caller aborts, or when `ms` elapses.
 *
 * `AbortSignal.any` would do this in one line, but it is Safari 17.4+ and
 * Chrome 116+ — recent enough that shipping it bare would throw a TypeError on
 * every request for anyone on an older iPhone, taking the whole feed with it.
 * `AbortSignal.timeout` is much older and safe to assume.
 */
function withDeadline(ms: number, signal?: AbortSignal): AbortSignal {
  const timeout = AbortSignal.timeout(ms);
  if (!signal) return timeout;
  if (typeof AbortSignal.any === "function") {
    return AbortSignal.any([signal, timeout]);
  }

  const controller = new AbortController();
  const abort = () => controller.abort();
  if (signal.aborted || timeout.aborted) {
    controller.abort();
  } else {
    signal.addEventListener("abort", abort, { once: true });
    timeout.addEventListener("abort", abort, { once: true });
  }
  return controller.signal;
}

async function getGamma<T>(
  path: string,
  query: Record<string, string | number | undefined>,
  _revalidate: number,
  signal?: AbortSignal
): Promise<T> {
  const url = new URL(`${EDGE}/gamma/${path}`);
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined) url.searchParams.set(key, String(value));
  }

  // Always `cache: "no-store"` here. Cloudflare Pages Functions mishandle
  // Next’s `next.revalidate` Cache API on large Gamma payloads (multi‑MB
  // `/events` lists), and the Worker already applies its own edge TTL.
  // Event-detail SSR stays small (`?slug=` / `/events/:id`).
  // Caller's abort (navigation, filter change) plus a hard timeout, so a stalled
  // request can never pin the feed on its skeleton forever.
  const response = await fetch(url.toString(), {
    cache: "no-store",
    headers: { accept: "application/json" },
    signal: withDeadline(20_000, signal),
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

export interface EventPage {
  events: PeakEvent[];
  /** Whether Gamma has more rows after this window. */
  hasMore: boolean;
  /** Total matching events upstream, when Gamma reports it. */
  total: number | null;
}

/**
 * One window of the browse feed.
 *
 * Uses `/events/pagination` rather than `/events` — same rows, but it also
 * returns `{hasMore, totalResults}`. Without those the client can only guess
 * from "did I get a full page?", which is wrong exactly when the last page is
 * full: you get a Next button that leads to nothing, and a count that reads
 * "24+" when 24 is the whole set.
 *
 * `signal` matters as much as the data. Switching category twice quickly fires
 * two requests, and the slower one must not be allowed to land on top of the
 * faster one.
 */
export async function fetchEventPage(options?: {
  limit?: number;
  offset?: number;
  sort?: SortKey;
  tagSlug?: string;
  signal?: AbortSignal;
}): Promise<EventPage> {
  const body = await getGamma<{
    data?: Record<string, unknown>[];
    pagination?: { hasMore?: boolean; totalResults?: number };
  }>(
    "events/pagination",
    {
      limit: options?.limit ?? 24,
      offset: options?.offset ?? 0,
      order: options?.sort ?? DEFAULT_SORT,
      ascending: "false",
      tag_slug: options?.tagSlug,
      ...SHOWCASE,
    },
    60,
    options?.signal
  );

  const raw = Array.isArray(body?.data) ? body.data : [];
  const events = raw
    .filter(isListEligible)
    .map(mapEvent)
    .filter((e): e is PeakEvent => e !== null);

  const total =
    typeof body?.pagination?.totalResults === "number"
      ? body.pagination.totalResults
      : null;

  return {
    events,
    // `isListEligible` drops rows Gamma still calls open (finished games with a
    // past endDate), so a window can come back short while more remain. Trust
    // upstream's flag, and fall back to the raw — not filtered — length.
    hasMore: body?.pagination?.hasMore ?? raw.length >= (options?.limit ?? 24),
    total,
  };
}

/** Paginated live events for the browse feed. */
export async function fetchEvents(options?: {
  limit?: number;
  offset?: number;
  sort?: SortKey;
  tagSlug?: string;
  signal?: AbortSignal;
}): Promise<PeakEvent[]> {
  const page = await fetchEventPage(options);
  return page.events;
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

/**
 * Several events in one request.
 *
 * Gamma accepts a repeated `id` parameter, so a watchlist of twenty markets is
 * one call rather than twenty. It used to fan out one request per saved market,
 * in parallel — and each of those carries every nested leg of its event, so a
 * modest watchlist opened with tens of megabytes in flight at once.
 *
 * Chunked because the query string is not unbounded, and because a single
 * oversized request failing would take the whole list with it.
 */
export async function fetchEventsByIds(
  ids: string[],
  signal?: AbortSignal
): Promise<Map<string, PeakEvent>> {
  const clean = [...new Set(ids.map((id) => id.trim()).filter(Boolean))];
  const found = new Map<string, PeakEvent>();
  if (clean.length === 0) return found;

  const CHUNK = 20;
  const chunks: string[][] = [];
  for (let i = 0; i < clean.length; i += CHUNK) {
    chunks.push(clean.slice(i, i + CHUNK));
  }

  const results = await Promise.all(
    chunks.map(async (chunk) => {
      const url = new URL(`${EDGE}/gamma/events`);
      for (const id of chunk) url.searchParams.append("id", id);
      url.searchParams.set("limit", String(chunk.length));
      try {
        const response = await fetch(url.toString(), {
          cache: "no-store",
          headers: { accept: "application/json" },
          signal: withDeadline(20_000, signal),
        });
        if (!response.ok) return [];
        const raw = (await response.json()) as unknown;
        return Array.isArray(raw) ? (raw as Record<string, unknown>[]) : [];
      } catch {
        // One bad chunk drops its own rows; the rest of the list still renders.
        return [];
      }
    })
  );

  for (const raw of results.flat()) {
    const event = mapEvent(raw);
    if (event) found.set(event.id, event);
  }
  return found;
}

