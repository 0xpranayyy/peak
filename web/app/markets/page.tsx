import type { Metadata } from "next";
import { fetchEvents, fetchTags, type PeakEvent, type SortKey, type Tag } from "@/lib/gamma";
import { MarketCard } from "@/components/MarketCard";
import { Filters } from "@/components/Filters";

export const runtime = "edge";
export const dynamic = "force-dynamic";

const SORTS: SortKey[] = ["volume24hr", "volume", "liquidity", "endDate"];
const PAGE_SIZE = 36;

type Props = {
  searchParams: Promise<{ tag?: string; sort?: string; page?: string }>;
};

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const { tag } = await searchParams;
  if (!tag) {
    return {
      title: "Markets",
      description: "Live Polymarket prediction markets with current odds and volume.",
    };
  }
  const label = tag.replace(/-/g, " ");
  return {
    title: `${label} markets`,
    description: `Live ${label} prediction markets with current odds and volume.`,
  };
}

function pageHref(opts: {
  tag?: string;
  sort: SortKey;
  page: number;
}): string {
  const params = new URLSearchParams();
  if (opts.tag) params.set("tag", opts.tag);
  if (opts.sort !== "volume24hr") params.set("sort", opts.sort);
  if (opts.page > 1) params.set("page", String(opts.page));
  const q = params.toString();
  return q ? `/markets?${q}` : "/markets";
}

export default async function MarketsPage({ searchParams }: Props) {
  const params = await searchParams;
  const activeTag = params.tag?.trim() || undefined;
  const activeSort: SortKey = SORTS.includes(params.sort as SortKey)
    ? (params.sort as SortKey)
    : "volume24hr";
  const page = Math.max(1, Number(params.page) || 1);
  const offset = (page - 1) * PAGE_SIZE;

  const [events, tags] = await Promise.all([
    fetchEvents({
      limit: PAGE_SIZE,
      offset,
      sort: activeSort,
      tagSlug: activeTag,
    }).catch((): PeakEvent[] => []),
    fetchTags(24).catch((): Tag[] => []),
  ]);

  const hasMore = events.length >= PAGE_SIZE;
  const hasPrev = page > 1;

  return (
    <div className="shell page-body">
      <div className="page-head">
        <div>
          <h1>Markets</h1>
          <p>Live odds from Polymarket. Sign in to trade.</p>
        </div>
        <form className="search" action="/search" role="search">
          <input
            type="search"
            name="q"
            placeholder="Search markets"
            aria-label="Search markets"
          />
          <button type="submit">Search</button>
        </form>
      </div>

      <Filters tags={tags} activeTag={activeTag} activeSort={activeSort} />

      {events.length === 0 ? (
        <p className="empty">
          {activeTag
            ? "No live markets in this category right now."
            : page > 1
              ? "No more markets on this page."
              : "Markets are unavailable right now. Try again in a moment."}
        </p>
      ) : (
        <div className="market-list">
          <div className="market-list__head" aria-hidden="true">
            <span>Market</span>
            <span>Chance</span>
          </div>
          {events.map((event) => (
            <MarketCard key={event.id} event={event} />
          ))}
        </div>
      )}

      {(hasPrev || hasMore) && (
        <nav className="pager" aria-label="Markets pages">
          {hasPrev ? (
            <a
              className="btn"
              href={pageHref({ tag: activeTag, sort: activeSort, page: page - 1 })}
            >
              ← Previous
            </a>
          ) : (
            <span />
          )}
          <span className="pager__label">Page {page}</span>
          {hasMore ? (
            <a
              className="btn"
              href={pageHref({ tag: activeTag, sort: activeSort, page: page + 1 })}
            >
              Next →
            </a>
          ) : (
            <span />
          )}
        </nav>
      )}
    </div>
  );
}
