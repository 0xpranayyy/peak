import type { PeakEvent } from "@/lib/gamma";
import { compactUsd, endsIn, percent } from "@/lib/format";

/** Dense market row for the exchange feed — real volume only, no fake change. */
export function MarketCard({ event }: { event: PeakEvent }) {
  const probability = event.displayProbability;
  const isMulti = event.markets.length > 1;
  const ends = endsIn(event.endDate);
  const body = (
    <>
      <div className="market-row__main">
        <div className="market-row__title">{event.title}</div>
        <div className="market-row__meta">
          {ends ? <span>{ends}</span> : null}
          {isMulti ? <span>{event.markets.length} markets</span> : null}
        </div>
      </div>
      <div className="market-row__cell mono" title="Total volume">
        {compactUsd(event.volume)}
      </div>
      <div className="market-row__cell mono" title="24h volume">
        {event.volume24hr > 0 ? compactUsd(event.volume24hr) : "—"}
      </div>
      <div className="market-row__price">
        {isMulti ? (
          <>
            <b className="market-row__multi">{event.markets.length}</b>
            <span>mkts</span>
          </>
        ) : probability !== null ? (
          <>
            <b>{percent(probability)}</b>
            <span>chance</span>
            <div className="bar" aria-hidden="true">
              <i style={{ width: `${probability * 100}%` }} />
            </div>
          </>
        ) : (
          <span className="market-row__na">—</span>
        )}
      </div>
    </>
  );

  if (!event.slug) {
    return (
      <div className="market-row market-row--disabled" aria-disabled="true">
        {body}
      </div>
    );
  }

  return (
    <a
      className="market-row"
      href={`/event/${event.slug}`}
      aria-label={`${event.title}${probability != null ? `, ${percent(probability)}` : ""}`}
    >
      {body}
    </a>
  );
}
