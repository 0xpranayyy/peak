"use client";

import { useEffect, useState } from "react";
import { searchEvents, type PeakEvent } from "@/lib/gamma";
import { MarketCard } from "@/components/MarketCard";

/** Browser-side search — same Gamma size reason as the markets feed. */
export function SearchClient({ query }: { query: string }) {
  const [events, setEvents] = useState<PeakEvent[] | null>(query ? null : []);
  const [error, setError] = useState(false);

  useEffect(() => {
    if (!query) {
      setEvents([]);
      setError(false);
      return;
    }
    let cancelled = false;
    setEvents(null);
    setError(false);
    searchEvents(query)
      .then((rows) => {
        if (!cancelled) setEvents(rows);
      })
      .catch(() => {
        if (!cancelled) {
          setEvents([]);
          setError(true);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [query]);

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
      ) : events == null ? (
        <p className="empty">Searching…</p>
      ) : events.length === 0 ? (
        <p className="empty">
          {error
            ? "Search is unavailable right now. Try again in a moment."
            : `Nothing matched “${query}”. Try a shorter or more general term.`}
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
