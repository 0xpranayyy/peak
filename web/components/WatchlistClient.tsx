"use client";

import { useEffect, useState } from "react";
import { useWatchlist } from "@/lib/watchlist-hook";
import { fetchEventById, type PeakEvent } from "@/lib/gamma";
import { compactUsd, endsIn, percent } from "@/lib/format";

export function WatchlistClient() {
  const { ids, remove } = useWatchlist();
  const [events, setEvents] = useState<PeakEvent[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    if (ids.length === 0) {
      setEvents([]);
      setError(null);
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    (async () => {
      const loaded: PeakEvent[] = [];
      let failures = 0;
      for (const id of ids) {
        const event = await fetchEventById(id).catch(() => null);
        if (event) loaded.push(event);
        else failures += 1;
      }
      if (cancelled) return;
      const map = new Map(loaded.map((e) => [e.id, e]));
      const ordered = ids
        .map((id) => map.get(id))
        .filter((e): e is PeakEvent => Boolean(e));
      setEvents(ordered);
      setError(
        ordered.length === 0 && failures > 0
          ? "Couldn’t load watchlist markets. Try again."
          : null
      );
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [ids]);

  return (
    <div className="page-body">
      <div className="page-head">
        <div>
          <h1>Watchlist</h1>
          <p>Markets you save on this device. Empty until you add real markets.</p>
        </div>
      </div>

      {ids.length === 0 ? (
        <p className="empty">
          Nothing saved yet. Open a market and tap Watch, or{" "}
          <a href="/markets" className="text-link">
            browse markets
          </a>
          .
        </p>
      ) : loading && events.length === 0 ? (
        <p className="empty empty--compact">Loading watchlist…</p>
      ) : error && events.length === 0 ? (
        <p className="empty">{error}</p>
      ) : (
        <div className="market-list">
          <div className="market-list__head market-list__head--watch" aria-hidden="true">
            <span>Market</span>
            <span>Chance</span>
            <span />
          </div>
          {events.map((event) => {
            const probability = event.displayProbability;
            const ends = endsIn(event.endDate);
            const href = event.slug ? `/event/${event.slug}` : "#";
            return (
              <div key={event.id} className="market-row market-row--watch">
                <a href={href} className="market-row__main">
                  <div className="market-row__title">{event.title}</div>
                  <div className="market-row__meta">
                    <span>{compactUsd(event.volume24hr)} 24h</span>
                    {ends ? <span>{ends}</span> : null}
                  </div>
                </a>
                <div className="market-row__price">
                  {event.markets.length > 1 ? (
                    <>
                      <b>{event.markets.length}</b>
                      <span>outcomes</span>
                    </>
                  ) : probability != null ? (
                    <>
                      <b>{percent(probability)}</b>
                      <span>chance</span>
                    </>
                  ) : (
                    <span>—</span>
                  )}
                </div>
                <button
                  type="button"
                  className="btn btn--ghost"
                  onClick={() => remove(event.id)}
                  aria-label={`Remove ${event.title} from watchlist`}
                >
                  Remove
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
