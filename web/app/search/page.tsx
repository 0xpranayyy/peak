import type { Metadata } from "next";
import { searchEvents, type PeakEvent } from "@/lib/gamma";
import { MarketCard } from "@/components/MarketCard";

export const runtime = "edge";

type Props = { searchParams: Promise<{ q?: string }> };

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const { q } = await searchParams;
  return {
    title: q ? `“${q}”` : "Search",
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
    <div className="shell page-body">
      <div className="page-head">
        <div>
          <h1>Search</h1>
          <p>Find live markets by title or topic.</p>
        </div>
        <form className="search" action="/search" role="search">
          <input
            type="search"
            name="q"
            defaultValue={query}
            placeholder="Search markets"
            aria-label="Search markets"
          />
          <button type="submit">Search</button>
        </form>
      </div>

      {!query ? (
        <p className="empty">
          Type something to search live markets, or{" "}
          <a className="text-link" href="/markets">
            browse trending
          </a>
          .
        </p>
      ) : events.length === 0 ? (
        <p className="empty">
          Nothing matched “{query}”. Try a shorter or more general term.
        </p>
      ) : (
        <>
          <p className="result-meta">
            {events.length} market{events.length === 1 ? "" : "s"} for “{query}”
          </p>
          <div className="market-list">
            <div className="market-list__head" aria-hidden="true">
              <span>Market</span>
              <span>Chance</span>
            </div>
            {events.map((event) => (
              <MarketCard key={event.id} event={event} />
            ))}
          </div>
        </>
      )}
    </div>
  );
}
