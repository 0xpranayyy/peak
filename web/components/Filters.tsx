import { DEFAULT_SORT, type SortKey } from "@/lib/gamma";
import { CATEGORIES, type CategoryMatch } from "@/lib/categories";

const SORTS: { key: SortKey; label: string }[] = [
  { key: "volume24hr", label: "Trending" },
  { key: "volume", label: "Volume" },
  { key: "liquidity", label: "Liquidity" },
  { key: "endDate", label: "Ending" },
];

/**
 * Filters are plain links — shareable, back-button-correct, and no JavaScript
 * needed to change what you are looking at.
 *
 * The second row only appears once you are inside a section that has one. It is
 * the difference between "Sports" and "Sports → Cricket", and showing every
 * sport up front would bury the ten top-level sections under sixty chips.
 */
export function Filters({
  match,
  activeSort,
}: {
  match?: CategoryMatch;
  activeSort: SortKey;
}) {
  const href = (tag?: string, sort?: SortKey) => {
    const params = new URLSearchParams();
    if (tag) params.set("tag", tag);
    if (sort && sort !== DEFAULT_SORT) params.set("sort", sort);
    const query = params.toString();
    return query ? `/markets?${query}` : "/markets";
  };

  const parent = match?.parent;
  const children = parent?.children ?? [];

  return (
    <div className="filters">
      <nav className="tabs" aria-label="Sort markets">
        {SORTS.map((sort) => (
          <a
            key={sort.key}
            className={sort.key === activeSort ? "is-on" : undefined}
            href={href(match?.slug, sort.key)}
          >
            {sort.label}
          </a>
        ))}
      </nav>

      <nav className="chips chips--scroll" aria-label="Filter by category">
        <a
          className={`chip${!match ? " chip--on" : ""}`}
          href={href(undefined, activeSort)}
        >
          All
        </a>
        {CATEGORIES.map((cat) => (
          <a
            key={cat.id}
            className={`chip${cat.id === parent?.id ? " chip--on" : ""}`}
            href={href(cat.slug, activeSort)}
          >
            {cat.label}
          </a>
        ))}
      </nav>

      {children.length > 0 ? (
        <nav
          className="chips chips--scroll chips--sub"
          aria-label={`Filter within ${parent?.label}`}
        >
          <a
            className={`chip chip--sm${!match?.child ? " chip--on" : ""}`}
            href={href(parent?.slug, activeSort)}
          >
            All {parent?.label}
          </a>
          {children.map((child) => (
            <a
              key={child.id}
              className={`chip chip--sm${
                child.id === match?.child?.id ? " chip--on" : ""
              }`}
              href={href(child.slug, activeSort)}
            >
              {child.label}
            </a>
          ))}
        </nav>
      ) : null}
    </div>
  );
}
