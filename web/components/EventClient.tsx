"use client";

import { Suspense, useEffect, useState } from "react";
import { fetchEventBySlug, type PeakEvent } from "@/lib/gamma";
import { cents, compactUsd, endsIn, percent } from "@/lib/format";
import { EventTradePanel } from "@/components/EventTradePanel";
import { WatchlistToggle } from "@/components/WatchlistToggle";

/**
 * Event detail loads in the browser on purpose.
 *
 * Even `?slug=` Gamma payloads are often 100KB+ with nested markets.
 * Cloudflare Pages Functions CPU-trip while SSR-parsing them, which 404s
 * live markets even when edge.peakapp.site returns 200. Worker CORS already
 * allows the browser to fetch the same URL.
 */
export function EventClient({ slug }: { slug: string }) {
  const [event, setEvent] = useState<PeakEvent | null | undefined>(undefined);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setEvent(undefined);
    setFailed(false);
    (async () => {
      try {
        const next = await fetchEventBySlug(slug);
        if (cancelled) return;
        setEvent(next);
        if (!next) setFailed(true);
      } catch {
        if (cancelled) return;
        setEvent(null);
        setFailed(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [slug]);

  if (event === undefined) {
    return (
      <div className="shell detail">
        <a className="detail__back" href="/markets">
          ← Markets
        </a>
        <p className="empty">Loading market…</p>
      </div>
    );
  }

  if (!event || failed) {
    return (
      <div className="shell not-found">
        <h1>This market isn’t here.</h1>
        <p>
          It may have resolved and been removed upstream, or the link may be
          mistyped. Live markets are under Markets.
        </p>
        <p className="not-found__cta">
          <a className="cta" href="/markets">
            Browse markets
          </a>
        </p>
      </div>
    );
  }

  const ends = endsIn(event.endDate);

  return (
    <div className="shell detail">
      <a className="detail__back" href="/markets">
        ← Markets
      </a>

      <div className="detail__layout">
        <div className="detail__main">
          <div className="detail__head">
            {event.imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img className="detail__art" src={event.imageUrl} alt="" />
            ) : null}
            <div>
              <h1>{event.title}</h1>
              <div className="detail__meta">
                <span>{compactUsd(event.volume)} volume</span>
                <span>{compactUsd(event.liquidity)} liquidity</span>
                {ends ? <span>{ends}</span> : null}
              </div>
              <div className="detail__tools">
                <WatchlistToggle eventId={event.id} />
              </div>
            </div>
          </div>

          {event.description ? (
            <p className="detail__desc">{event.description}</p>
          ) : null}

          <div className="outcomes">
            {event.markets.map((market) => {
              const probability = market.yesPrice;
              return (
                <div key={market.id} className="outcome">
                  <span className="outcome__q">{market.question}</span>
                  <span className="outcome__price">
                    {probability !== null ? cents(probability) : "—"}
                  </span>

                  {probability !== null ? (
                    <div className="bar outcome__bar">
                      <i style={{ width: `${probability * 100}%` }} />
                    </div>
                  ) : null}

                  <div className="outcome__sub">
                    {probability !== null ? (
                      <span>{percent(probability)} chance</span>
                    ) : (
                      <span>Not priced</span>
                    )}
                    <span>{compactUsd(market.volume)} volume</span>
                    {market.closed ? <span>Closed</span> : null}
                  </div>
                </div>
              );
            })}
          </div>

          <p className="notice">
            <b>Prices are live, not advice.</b> An outcome at 70¢ prices a ~70%
            chance — it is not a prediction of what will happen, and it moves.
          </p>
        </div>

        <Suspense
          fallback={
            <div className="detail__aside">
              <div className="ticket-fallback">Loading ticket…</div>
            </div>
          }
        >
          <EventTradePanel markets={event.markets} />
        </Suspense>
      </div>
    </div>
  );
}
