import type { Metadata } from "next";
import { Suspense } from "react";
import { notFound } from "next/navigation";
import { fetchEventBySlug } from "@/lib/gamma";
import { cents, compactUsd, endsIn, percent } from "@/lib/format";
import { EventTradePanel } from "@/components/EventTradePanel";

export const runtime = "edge";
export const dynamic = "force-dynamic";

type Props = { params: Promise<{ slug: string }> };

/**
 * Per-market metadata is the whole reason this app is server-rendered. A share
 * of a market link should preview the actual question and the current odds,
 * and search should be able to index them.
 */
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const event = await fetchEventBySlug(slug).catch(() => null);
  if (!event) return { title: "Market not found" };

  const probability = event.displayProbability;
  const odds = probability !== null ? ` — ${percent(probability)} chance` : "";
  const description =
    event.description?.slice(0, 180) ??
    `Live odds, volume and resolution date for ${event.title}.`;

  return {
    title: event.title,
    description,
    openGraph: {
      title: `${event.title}${odds}`,
      description,
      images: event.imageUrl ? [event.imageUrl] : undefined,
      url: `/event/${slug}`,
    },
  };
}

export default async function EventPage({ params }: Props) {
  const { slug } = await params;
  const event = await fetchEventBySlug(slug).catch(() => null);
  if (!event) notFound();

  const ends = endsIn(event.endDate);

  return (
    <div className="shell detail">
      <a className="detail__back" href="/markets">
        ← All markets
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
            <b>Prices are live, not advice.</b> An outcome trading at 70¢ means the
            market prices it near a 70% chance — it is not a prediction of what will
            happen, and it moves.
          </p>
        </div>

        <Suspense fallback={<div className="detail__aside"><p className="empty">Loading ticket…</p></div>}>
          <EventTradePanel markets={event.markets} />
        </Suspense>
      </div>
    </div>
  );
}
