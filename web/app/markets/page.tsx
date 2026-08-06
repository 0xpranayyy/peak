import type { Metadata } from "next";
import { fetchEvents, fetchTags, type PeakEvent, type SortKey, type Tag } from "@/lib/gamma";
import { MarketCard } from "@/components/MarketCard";
import { Filters } from "@/components/Filters";

export const runtime = "edge";
// Rendered per request. `next-on-pages` does not support ISR, so `revalidate`
// would be a no-op on Cloudflare Pages anyway — and making it explicit keeps
// `next build` from needing live market data just to produce a bundle.
export const dynamic = "force-dynamic";

const SORTS: SortKey[] = ["volume24hr", "volume", "liquidity", "endDate"];

type Props = {
  searchParams: Promise<{ tag?: string; sort?: string }>;
};

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const { tag } = await searchParams;
  if (!tag) {
    return {
      title: "All markets",
      description:
        "Every live Polymarket prediction market, with current odds, volume and resolution dates.",
    };
  }
  const label = tag.replace(/-/g, " ");
  return {
    title: `${label} markets`,
    description: `Live ${label} prediction markets with current odds, volume and resolution dates.`,
  };
}

export default async function HomePage({ searchParams }: Props) {
  const params = await searchParams;
  const activeTag = params.tag?.trim() || undefined;
  const activeSort: SortKey = SORTS.includes(params.sort as SortKey)
    ? (params.sort as SortKey)
    : "volume24hr";

  // The feed and the chips fail independently. Losing categories should not
  // cost the user the markets, and vice versa.
  const [events, tags] = await Promise.all([
    fetchEvents({ limit: 36, sort: activeSort, tagSlug: activeTag }).catch(
      (): PeakEvent[] => []
    ),
    fetchTags(24).catch((): Tag[] => []),
  ]);

  return (
    <>
      <section className="hero hero--feed">
        <div className="shell">
          <h1>Live markets</h1>
          <p>
            Current odds from Polymarket. Sign in to trade from this browser —
            Peak never asks for a seed phrase on the web.
          </p>
          <form className="search" action="/search" role="search">
            <input
              type="search"
              name="q"
              placeholder="Search markets — elections, rates, sport…"
              aria-label="Search markets"
            />
            <button type="submit">Search</button>
          </form>
        </div>
      </section>

      <div className="shell">
        <Filters tags={tags} activeTag={activeTag} activeSort={activeSort} />

        {events.length === 0 ? (
          <p className="empty">
            {activeTag
              ? "No live markets in this category right now."
              : "Markets are unavailable right now. Try again in a moment."}
          </p>
        ) : (
          <div className="grid">
            {events.map((event) => (
              <MarketCard key={event.id} event={event} />
            ))}
          </div>
        )}
      </div>
    </>
  );
}
