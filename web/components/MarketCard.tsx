import type { PeakEvent } from "@/lib/gamma";
import { compactUsd, endsIn, percent } from "@/lib/format";

/** Dense market row for the exchange feed — one probability, real volume. */
export function MarketCard({ event }: { event: PeakEvent }) {
  const probability = event.displayProbability;
  const isMulti = event.markets.length > 1;
  const ends = endsIn(event.endDate);
  const href = event.slug ? `/event/${event.slug}` : "#";

  return (
    <a className="market-row" href={href}>
      <div className="market-row__main">
        <div className="market-row__title">{event.title}</div>
        <div className="market-row__meta">
          <span>{compactUsd(event.volume24hr)} 24h</span>
          {ends ? <span>{ends}</span> : null}
        </div>
      </div>
      <div className="market-row__price">
        {isMulti ? (
          <>
            <b>{event.markets.length}</b>
            <span>outcomes</span>
          </>
        ) : probability !== null ? (
          <>
            <b>{percent(probability)}</b>
            <span>chance</span>
            <div className="bar">
              <i style={{ width: `${probability * 100}%` }} />
            </div>
          </>
        ) : (
          <span>—</span>
        )}
      </div>
    </a>
  );
}
