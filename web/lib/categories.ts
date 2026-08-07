/**
 * Curated browse taxonomy — two levels, mirroring how Polymarket actually files
 * markets.
 *
 * Raw Gamma `/tags` is unusable as navigation: it returns 100 unordered rows out
 * of thousands, mixes real sections with athletes, one-offs and typos
 * ("virgins", "product-marekt-fit"), and carries no parent/child link at all.
 * So the hierarchy is curated here — but curated *from* live data, not invented:
 * every slug below was checked against `/gamma/events?tag_slug=` and kept only
 * when it returned real open markets.
 *
 * Two consequences worth knowing:
 *
 *  - Slug and label often disagree, because Gamma's slugs are historical.
 *    "Culture" is `pop-culture` (a bare `culture` tag exists and is permanently
 *    empty — it was wired up here before and silently showed nothing), and NFL
 *    markets are tagged `football`, which would read as soccer to most of the
 *    world.
 *  - Seasonal sections empty out. NHL and F1 are thin out of season and the
 *    feed's own empty state covers that. That is different from a wrong slug:
 *    these come back on their own.
 *
 * Sub-slugs are globally unique, so browsing stays on one `?tag=` parameter and
 * every existing link keeps working.
 */

export type Category = {
  id: string;
  label: string;
  /** Gamma `tag_slug`. */
  slug: string;
  /** Narrower sections within this one. */
  children?: Category[];
};

export const CATEGORIES: Category[] = [
  {
    id: "politics",
    label: "Politics",
    slug: "politics",
    children: [
      { id: "trump", label: "Trump", slug: "trump" },
      { id: "p-elections", label: "Elections", slug: "elections" },
      { id: "geopolitics", label: "Geopolitics", slug: "geopolitics" },
      { id: "congress", label: "Congress", slug: "congress" },
    ],
  },
  {
    id: "elections",
    label: "Elections",
    slug: "elections",
    children: [
      { id: "us-election", label: "US Election", slug: "us-presidential-election" },
      { id: "midterms", label: "Midterms", slug: "midterms" },
      { id: "primaries", label: "Primaries", slug: "primaries" },
      { id: "house", label: "House", slug: "house-elections" },
      { id: "senate", label: "Senate", slug: "senate-elections" },
      { id: "global-elections", label: "Global", slug: "global-elections" },
    ],
  },
  {
    id: "crypto",
    label: "Crypto",
    slug: "crypto",
    children: [
      { id: "bitcoin", label: "Bitcoin", slug: "bitcoin" },
      { id: "ethereum", label: "Ethereum", slug: "ethereum" },
      { id: "solana", label: "Solana", slug: "solana" },
      { id: "xrp", label: "XRP", slug: "xrp" },
      { id: "crypto-prices", label: "Prices", slug: "crypto-prices" },
    ],
  },
  {
    id: "sports",
    label: "Sports",
    slug: "sports",
    children: [
      { id: "soccer", label: "Soccer", slug: "soccer" },
      { id: "basketball", label: "Basketball", slug: "basketball" },
      // Gamma files NFL markets under `football`; every title in there reads
      // "Pro Football: …". Labelling it "Football" would collide with soccer.
      { id: "nfl", label: "NFL", slug: "football" },
      { id: "baseball", label: "Baseball", slug: "baseball" },
      { id: "cricket", label: "Cricket", slug: "cricket" },
      { id: "tennis", label: "Tennis", slug: "tennis" },
      { id: "esports", label: "Esports", slug: "esports" },
      { id: "ufc", label: "UFC", slug: "ufc" },
      { id: "golf", label: "Golf", slug: "golf" },
      { id: "rugby", label: "Rugby", slug: "rugby" },
      { id: "nhl", label: "NHL", slug: "nhl" },
      { id: "f1", label: "F1", slug: "formula1" },
    ],
  },
  {
    id: "finance",
    label: "Finance",
    slug: "business",
    children: [
      { id: "stocks", label: "Stocks", slug: "stocks" },
      { id: "economy", label: "Economy", slug: "economy" },
      { id: "fed", label: "Fed", slug: "fed" },
      { id: "inflation", label: "Inflation", slug: "inflation" },
      { id: "earnings", label: "Earnings", slug: "earnings" },
      { id: "ipos", label: "IPOs", slug: "ipos" },
    ],
  },
  {
    id: "tech",
    label: "Tech",
    slug: "tech",
    children: [
      { id: "big-tech", label: "Big Tech", slug: "big-tech" },
      { id: "t-openai", label: "OpenAI", slug: "openai" },
      { id: "t-anthropic", label: "Anthropic", slug: "anthropic" },
      { id: "nvidia", label: "NVIDIA", slug: "nvidia" },
      { id: "google", label: "Google", slug: "google" },
      { id: "compute", label: "Compute", slug: "compute" },
    ],
  },
  {
    id: "ai",
    label: "AI",
    slug: "ai",
    children: [
      { id: "ai-rankings", label: "Rankings", slug: "ai-rankings" },
      { id: "ai-releases", label: "Releases", slug: "ai-releases" },
      { id: "ai-benchmarks", label: "Benchmarks", slug: "ai-benchmarks" },
    ],
  },
  {
    id: "culture",
    label: "Culture",
    // Not `culture` — that tag exists and is always empty.
    slug: "pop-culture",
    children: [
      { id: "awards", label: "Awards", slug: "awards" },
      { id: "movies", label: "Movies", slug: "movies" },
      { id: "music", label: "Music", slug: "music" },
      { id: "celebrities", label: "Celebrities", slug: "celebrities" },
      { id: "tv", label: "TV", slug: "tv" },
    ],
  },
  {
    id: "science",
    label: "Science",
    slug: "science",
    children: [
      { id: "weather", label: "Weather", slug: "weather" },
      { id: "climate", label: "Climate", slug: "climate-science" },
      { id: "space", label: "Space", slug: "space" },
      { id: "spacex", label: "SpaceX", slug: "spacex" },
      { id: "disasters", label: "Disasters", slug: "natural-disasters" },
      { id: "pandemics", label: "Pandemics", slug: "pandemics" },
    ],
  },
  {
    id: "world",
    label: "World",
    slug: "world",
    children: [
      { id: "iran", label: "Iran", slug: "iran" },
      { id: "russia", label: "Russia", slug: "russia" },
      { id: "israel", label: "Israel", slug: "israel" },
      { id: "middle-east", label: "Middle East", slug: "middle-east" },
      { id: "ukraine", label: "Ukraine", slug: "ukraine" },
      { id: "china", label: "China", slug: "china" },
      { id: "foreign-policy", label: "Foreign Policy", slug: "foreign-policy" },
    ],
  },
];

/** Where a resolved category sits in the tree. */
export type CategoryMatch = {
  /** The top-level section to highlight, and whose children to offer. */
  parent: Category;
  /** The narrower section, when the URL points at one. */
  child?: Category;
  /** The slug to send to Gamma — the child's when present. */
  slug: string;
};

const INDEX = new Map<string, CategoryMatch>();

for (const parent of CATEGORIES) {
  const match: CategoryMatch = { parent, slug: parent.slug };
  // Parents are indexed first and never overwritten below, so a slug that is
  // both a section and someone's child ("elections") resolves to the section.
  INDEX.set(parent.slug, match);
  INDEX.set(parent.id, match);

  for (const child of parent.children ?? []) {
    const childMatch: CategoryMatch = { parent, child, slug: child.slug };
    if (!INDEX.has(child.slug)) INDEX.set(child.slug, childMatch);
    if (!INDEX.has(child.id)) INDEX.set(child.id, childMatch);
  }
}

/** Resolve a URL `?tag=` value to a place in the taxonomy, or undefined. */
export function categoryFromSlug(
  slug: string | undefined | null
): CategoryMatch | undefined {
  if (!slug) return undefined;
  return INDEX.get(slug.trim().toLowerCase());
}
