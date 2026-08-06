import type { PeakEvent } from "@/lib/gamma";
import { compactUsd, endsIn, percent } from "@/lib/format";

/**
 * Feed card. Deliberately shows one number — the headline probability.
 *
 * Multi-market events (e.g. "who wins the election") have no single honest
 * headline, so those show an outcome count instead of pretending the first
 * market speaks for the whole event.
 */
export function MarketCard({ event }: { event: PeakEvent }) {
  const probability = event.displayProbability;
  const isMulti = event.markets.length > 1;
  const ends = endsIn(event.endDate);

  return (
    <a className="card" href={event.slug ? `/event/${event.slug}` : "#"}>
      <div className="card__head">
        {event.imageUrl ? (
          // Third-party CDN art in a 44px box — Next's optimizer earns nothing.
          // eslint-disable-next-line @next/next/no-img-element
          <img className="card__art" src={event.imageUrl} alt="" loading="lazy" />
        ) : null}
        <span className="card__title">{event.title}</span>
      </div>

      {isMulti ? (
        <div className="card__odds">
          <b>{event.markets.length}</b>
          <span>outcomes</span>
        </div>
      ) : probability !== null ? (
        <>
          <div className="card__odds">
            <b>{percent(probability)}</b>
            <span>chance</span>
          </div>
          <div className="bar">
            <i style={{ width: `${probability * 100}%` }} />
          </div>
        </>
      ) : null}

      <div className="card__foot">
        <span>{compactUsd(event.volume24hr)} 24h</span>
        {ends ? <span>{ends}</span> : null}
      </div>
    </a>
  );
}
