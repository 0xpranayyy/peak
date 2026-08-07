"use client";

import { useEffect, useState } from "react";
import { useWatchlist } from "@/lib/watchlist-hook";
import { fetchEventsByIds, headlineOdds, type PeakEvent } from "@/lib/gamma";
import { EventThumb } from "@/components/MarketCard";
import { compactUsd, endsIn, percent } from "@/lib/format";

export function WatchlistClient() {
  const { ids, remove } = useWatchlist();
  const [events, setEvents] = useState<PeakEvent[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (ids.length === 0) {
      setEvents([]);
      setError(null);
      setLoading(false);
      return;
    }
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    (async () => {
      const found = await fetchEventsByIds(ids, controller.signal);
      if (controller.signal.aborted) return;
      // Keep the saved order rather than upstream's.
      const ordered = ids
        .map((id) => found.get(id))
        .filter((e): e is PeakEvent => Boolean(e));
      setEvents(ordered);
      setError(
        ordered.length === 0
          ? "Couldn’t load watchlist markets. Try again."
          : null
      );
      setLoading(false);
    })();
    return () => controller.abort();
  }, [ids]);

  return (
    <div className="page-body">
      <div className="page-head">
        <div>
          <h1>Watchlist</h1>
          <p>Markets you save on this device.</p>
        </div>
      </div>

      {ids.length === 0 ? (
        <div className="empty-state">
          <p className="empty-state__title">Nothing saved yet</p>
          <p className="empty-state__body">
            Open a market and tap Watch to save it here.
          </p>
          <a className="btn btn--primary" href="/markets">
            Browse markets
          </a>
        </div>
      ) : loading && events.length === 0 ? (
        <p className="empty empty--compact">Loading watchlist…</p>
      ) : error && events.length === 0 ? (
        <div className="empty-state">
          <p className="empty-state__title">Couldn’t load</p>
          <p className="empty-state__body">{error}</p>
        </div>
      ) : (
        <div className="market-list">
          <div
            className="market-list__head market-list__head--watch"
            aria-hidden="true"
          >
            <span>Market</span>
            <span>Vol</span>
            <span>24h</span>
            <span>Chance</span>
            <span />
          </div>
          {events.map((event) => {
            const { probability, caption } = headlineOdds(event);
            const ends = endsIn(event.endDate);
            const href = event.slug ? `/event/${event.slug}` : null;
            return (
              <div key={event.id} className="market-row market-row--watch">
                <EventThumb event={event} />
                {href ? (
                  <a href={href} className="market-row__main">
                    <div className="market-row__title">{event.title}</div>
                    <div className="market-row__meta">
                      {ends ? <span>{ends}</span> : null}
                    </div>
                  </a>
                ) : (
                  <div className="market-row__main">
                    <div className="market-row__title">{event.title}</div>
                    <div className="market-row__meta">
                      {ends ? <span>{ends}</span> : null}
                    </div>
                  </div>
                )}
                <div className="market-row__cell mono">
                  {compactUsd(event.volume)}
                </div>
                <div className="market-row__cell mono">
                  {event.volume24hr > 0 ? compactUsd(event.volume24hr) : "—"}
                </div>
                <div className="market-row__price">
                  {probability !== null ? (
                    <>
                      <b>{percent(probability)}</b>
                      <span title={caption}>{caption}</span>
                    </>
                  ) : (
                    <span className="market-row__na">—</span>
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
