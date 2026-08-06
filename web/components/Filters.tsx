import { DEFAULT_SORT, type SortKey } from "@/lib/gamma";
import { CATEGORIES } from "@/lib/categories";

const SORTS: { key: SortKey; label: string }[] = [
  { key: "volume", label: "Volume" },
  { key: "volume24hr", label: "Trending" },
  { key: "liquidity", label: "Liquidity" },
  { key: "endDate", label: "Ending" },
];

/**
 * Filters are plain links. Categories are curated (iOS MarketCategory),
 * not the raw Gamma tag dump.
 */
export function Filters({
  activeTag,
  activeSort,
}: {
  activeTag?: string;
  activeSort: SortKey;
}) {
  const href = (tag?: string, sort?: SortKey) => {
    const params = new URLSearchParams();
    if (tag) params.set("tag", tag);
    if (sort && sort !== DEFAULT_SORT) params.set("sort", sort);
    const query = params.toString();
    return query ? `/markets?${query}` : "/markets";
  };

  return (
    <div className="filters">
      <nav className="tabs" aria-label="Sort markets">
        {SORTS.map((sort) => (
          <a
            key={sort.key}
            className={sort.key === activeSort ? "is-on" : undefined}
            href={href(activeTag, sort.key)}
          >
            {sort.label}
          </a>
        ))}
      </nav>

      <nav className="chips chips--scroll" aria-label="Filter by category">
        <a
          className={`chip${!activeTag ? " chip--on" : ""}`}
          href={href(undefined, activeSort)}
        >
          All
        </a>
        {CATEGORIES.map((cat) => (
          <a
            key={cat.id}
            className={`chip${
              cat.slug === activeTag || cat.id === activeTag ? " chip--on" : ""
            }`}
            href={href(cat.slug, activeSort)}
          >
            {cat.label}
          </a>
        ))}
      </nav>
    </div>
  );
}
