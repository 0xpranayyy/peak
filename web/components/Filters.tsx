import { DEFAULT_SORT, type Tag, type SortKey } from "@/lib/gamma";

const SORTS: { key: SortKey; label: string }[] = [
  { key: "volume", label: "Volume" },
  { key: "volume24hr", label: "Trending" },
  { key: "liquidity", label: "Liquidity" },
  { key: "endDate", label: "Ending" },
];

/**
 * Filters are plain links. Every combination is a shareable URL.
 */
export function Filters({
  tags,
  activeTag,
  activeSort,
}: {
  tags: Tag[];
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

      {tags.length > 0 ? (
        <nav className="chips chips--scroll" aria-label="Filter by category">
          <a
            className={`chip${!activeTag ? " chip--on" : ""}`}
            href={href(undefined, activeSort)}
          >
            All
          </a>
          {tags.map((tag) => (
            <a
              key={tag.id}
              className={`chip${tag.slug === activeTag ? " chip--on" : ""}`}
              href={href(tag.slug, activeSort)}
            >
              {tag.label}
            </a>
          ))}
        </nav>
      ) : null}
    </div>
  );
}
