import type { PeakEvent } from "@/lib/gamma";
import { headlineOdds } from "@/lib/gamma";
import { compactUsd, endsIn, percent } from "@/lib/format";

/** Dense market row for the exchange feed — real volume only, no fake change. */
export function MarketCard({ event }: { event: PeakEvent }) {
  const isMulti = event.markets.length > 1;
  const { probability, caption } = headlineOdds(event);
  const ends = endsIn(event.endDate);

  const body = (
    <>
      <EventThumb event={event} />
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
        {probability !== null ? (
          <>
            <b>{percent(probability)}</b>
            <span title={caption}>{caption}</span>
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
      aria-label={
        probability !== null
          ? `${event.title}, ${caption} ${percent(probability)}`
          : event.title
      }
    >
      {body}
    </a>
  );
}

/**
 * Event artwork, or a placeholder of the same size. The placeholder is not
 * decoration: without it the grid column collapses and every row below an
 * artless event sits a few pixels out of line with the rest.
 */
export function EventThumb({ event }: { event: PeakEvent }) {
  if (!event.imageUrl) {
    return <div className="market-row__thumb market-row__thumb--empty" aria-hidden="true" />;
  }
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      className="market-row__thumb"
      src={event.imageUrl}
      alt=""
      width={40}
      height={40}
      loading="lazy"
      decoding="async"
    />
  );
}
