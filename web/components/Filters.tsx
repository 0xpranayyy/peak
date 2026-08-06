import type { Tag, SortKey } from "@/lib/gamma";

const SORTS: { key: SortKey; label: string }[] = [
  { key: "volume24hr", label: "Trending" },
  { key: "volume", label: "Volume" },
  { key: "liquidity", label: "Liquidity" },
  { key: "endDate", label: "Ending" },
];

/**
 * Filters are plain links, not client state. Every combination is a real URL,
 * which is the point of server rendering: `/markets?tag=politics&sort=volume` is
 * shareable and indexable, and the page works with JS disabled.
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
    if (sort && sort !== "volume24hr") params.set("sort", sort);
    const query = params.toString();
    return query ? `/markets?${query}` : "/markets";
  };

  return (
    <div className="filters">
      <nav className="chips" aria-label="Sort markets">
        {SORTS.map((sort) => (
          <a
            key={sort.key}
            className={`chip${sort.key === activeSort ? " chip--on" : ""}`}
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
