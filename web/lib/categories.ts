/**
 * Curated browse taxonomy — mirrors iOS `MarketCategory`.
 * Raw Gamma `/tags` is mostly noise (athletes, typos, one-offs).
 */

export type Category = {
  id: string;
  label: string;
  /** Primary Gamma `tag_slug`. */
  slug: string;
};

export const CATEGORIES: Category[] = [
  { id: "politics", label: "Politics", slug: "politics" },
  { id: "elections", label: "Elections", slug: "elections" },
  { id: "crypto", label: "Crypto", slug: "crypto" },
  { id: "sports", label: "Sports", slug: "sports" },
  { id: "finance", label: "Finance", slug: "business" },
  { id: "tech", label: "Tech", slug: "tech" },
  { id: "ai", label: "AI", slug: "ai" },
  { id: "culture", label: "Culture", slug: "culture" },
  { id: "science", label: "Science", slug: "science" },
  { id: "world", label: "World", slug: "world" },
];

const SLUG_TO_CATEGORY = new Map<string, Category>();
for (const cat of CATEGORIES) {
  SLUG_TO_CATEGORY.set(cat.slug, cat);
  SLUG_TO_CATEGORY.set(cat.id, cat);
}

/** Resolve a URL `?tag=` value to a known category, or undefined. */
export function categoryFromSlug(slug: string | undefined | null): Category | undefined {
  if (!slug) return undefined;
  return SLUG_TO_CATEGORY.get(slug.trim().toLowerCase());
}
