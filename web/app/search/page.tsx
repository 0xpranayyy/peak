import type { Metadata } from "next";
import { searchEvents, type PeakEvent } from "@/lib/gamma";
import { MarketCard } from "@/components/MarketCard";

export const runtime = "edge";

type Props = { searchParams: Promise<{ q?: string }> };

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const { q } = await searchParams;
  return {
    title: q ? `“${q}”` : "Search",
    // Search result pages are thin and infinite; keeping them out of the index
    // protects the market pages, which are the content worth ranking.
    robots: { index: false, follow: true },
  };
}

export default async function SearchPage({ searchParams }: Props) {
  const { q } = await searchParams;
  const query = q?.trim() ?? "";

  const events: PeakEvent[] = query
    ? await searchEvents(query).catch((): PeakEvent[] => [])
    : [];

  return (
    <div className="shell detail">
      <form className="search search--page" action="/search" role="search">
        <input
          type="search"
          name="q"
          defaultValue={query}
          placeholder="Search markets"
          aria-label="Search markets"
        />
        <button type="submit">Search</button>
      </form>

      {!query ? (
        <p className="empty">Type something to search live markets.</p>
      ) : events.length === 0 ? (
        <p className="empty">
          Nothing matched “{query}”. Try a shorter or more general term.
        </p>
      ) : (
        <>
          <p className="detail__meta" style={{ marginTop: 24 }}>
            <span>
              {events.length} market{events.length === 1 ? "" : "s"} for “{query}”
            </span>
          </p>
          <div className="grid">
            {events.map((event) => (
              <MarketCard key={event.id} event={event} />
            ))}
          </div>
        </>
      )}
    </div>
  );
}
