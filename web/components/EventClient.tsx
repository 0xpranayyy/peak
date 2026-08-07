"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import {
  fetchEventBySlug,
  type PeakEvent,
} from "@/lib/gamma";
import { cents, compactUsd, endsIn, percent } from "@/lib/format";
import { WatchlistToggle } from "@/components/WatchlistToggle";
import { PriceChart } from "@/components/PriceChart";
import { OrderBookPanel } from "@/components/OrderBookPanel";
import { TradeTicket } from "@/components/TradeTicket";
import type { TopOfBook } from "@/lib/clob";

/**
 * Event detail = trading terminal.
 * Loads in the browser — Gamma payloads are too heavy for Pages SSR CPU.
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
      <div className="shell shell--wide terminal">
        <a className="detail__back" href="/markets">
          ← Markets
        </a>
        <div className="empty-state empty-state--terminal">
          <p className="empty-state__body">Loading market…</p>
        </div>
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

  return (
    <Suspense
      fallback={
        <div className="shell shell--wide terminal">
          <div className="empty-state empty-state--terminal">
            <p className="empty-state__body">Loading ticket…</p>
          </div>
        </div>
      }
    >
      <EventTerminal event={event} />
    </Suspense>
  );
}

function EventTerminal({ event }: { event: PeakEvent }) {
  const searchParams = useSearchParams();
  const preferredOutcome = searchParams.get("outcome") ?? undefined;
  const preferredAsset =
    searchParams.get("asset") ?? searchParams.get("tokenID") ?? undefined;
  const initialSide =
    searchParams.get("side")?.toUpperCase() === "SELL"
      ? ("SELL" as const)
      : ("BUY" as const);
  const sharesParam = Number(searchParams.get("shares"));
  const initialShares =
    Number.isFinite(sharesParam) && sharesParam > 0 ? sharesParam : undefined;

  const preferredMarketIndex = useMemo(() => {
    if (preferredAsset) {
      const byToken = event.markets.findIndex((m) =>
        m.clobTokenIds.includes(preferredAsset)
      );
      if (byToken >= 0) return byToken;
    }
    if (preferredOutcome) {
      const idx = event.markets.findIndex((m) =>
        m.outcomes.includes(preferredOutcome)
      );
      if (idx >= 0) return idx;
    }
    // No deep link: open on the leg the market itself considers most likely.
    // Gamma's leg order is arbitrary, so "first tradable" regularly landed on a
    // 1¢ tail outcome — a confusing thing to hand someone as the default ticket.
    let best = -1;
    let bestPrice = -1;
    event.markets.forEach((m, i) => {
      if (!m.active || m.closed || m.clobTokenIds.length === 0) return;
      const price = m.yesPrice ?? 0;
      if (best < 0 || price > bestPrice) {
        best = i;
        bestPrice = price;
      }
    });
    return best >= 0 ? best : 0;
  }, [event.markets, preferredAsset, preferredOutcome]);

  const [marketIndex, setMarketIndex] = useState(preferredMarketIndex);
  const market =
    event.markets[Math.min(marketIndex, event.markets.length - 1)] ??
    event.markets[0];

  const outcomes = market?.outcomes?.length ? market.outcomes : ["Yes", "No"];

  const resolveOutcomeIdx = useCallback(
    (m: typeof market) => {
      if (!m) return 0;
      const outs = m.outcomes.length ? m.outcomes : ["Yes", "No"];
      if (preferredAsset) {
        const idx = m.clobTokenIds.indexOf(preferredAsset);
        if (idx >= 0) return idx;
      }
      if (preferredOutcome) {
        const idx = outs.indexOf(preferredOutcome);
        if (idx >= 0) return idx;
      }
      const yes = outs.findIndex((o) => o.toLowerCase() === "yes");
      return yes >= 0 ? yes : 0;
    },
    [preferredAsset, preferredOutcome]
  );

  const [outcomeIdx, setOutcomeIdx] = useState(() =>
    resolveOutcomeIdx(event.markets[preferredMarketIndex])
  );
  const [top, setTop] = useState<TopOfBook | null>(null);

  useEffect(() => {
    setOutcomeIdx(resolveOutcomeIdx(market));
    setTop(null);
    // Only reset when the selected market row changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [market?.id, resolveOutcomeIdx]);

  const tokenID =
    market?.clobTokenIds[outcomeIdx] ?? market?.clobTokenIds[0] ?? null;
  const outcomeLabel = outcomes[outcomeIdx] ?? outcomes[0];
  const ends = endsIn(event.endDate);

  const onTopOfBook = useCallback((book: TopOfBook) => {
    setTop(book);
  }, []);

  if (!market) return null;

  const displayPrice =
    top?.mid ?? market.outcomePrices[outcomeIdx] ?? market.yesPrice ?? null;

  return (
    <div className="shell shell--wide terminal">
      <a className="detail__back" href="/markets">
        ← Markets
      </a>

      <div className="terminal__grid">
        {/* The header sits in the grid rather than the stage so that on a phone,
            where the ticket is hoisted above the chart, you still read what you
            are trading before you see the buy button. */}
        <header className="terminal__header">
          <div className="terminal__title-row">
            {event.imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img className="detail__art" src={event.imageUrl} alt="" />
            ) : null}
            <div className="terminal__title-block">
              <h1>{event.title}</h1>
              <div className="detail__meta">
                <span>{compactUsd(event.volume)} vol</span>
                {event.volume24hr > 0 ? (
                  <span>{compactUsd(event.volume24hr)} 24h</span>
                ) : null}
                <span>{compactUsd(event.liquidity)} liq</span>
                {ends ? <span>{ends}</span> : null}
                {displayPrice != null ? (
                  <span className="detail__meta-price mono">
                    {outcomeLabel} {percent(displayPrice)}
                  </span>
                ) : null}
              </div>
            </div>
            <div className="terminal__header-actions">
              <WatchlistToggle eventId={event.id} />
            </div>
          </div>
        </header>

        <div className="terminal__stage">
          <div className="terminal__panels">
            <PriceChart tokenID={tokenID} livePrice={displayPrice} />
            <OrderBookPanel tokenID={tokenID} onTopOfBook={onTopOfBook} />
          </div>

          {event.markets.length > 1 ? (
            <div
              className="terminal__strip"
              role="listbox"
              aria-label="Markets in this event"
            >
              <span className="terminal__strip-label">Markets</span>
              <div className="terminal__strip-scroll">
                {event.markets.map((m, i) => {
                  const p = m.yesPrice;
                  const on = i === marketIndex;
                  // `question` repeats the event title on every leg, so a strip
                  // of them reads as the same truncated sentence over and over.
                  // `shortTitle` is the leg's own name — "August 31", "NRFI".
                  const label = m.shortTitle ?? m.question;
                  return (
                    <button
                      key={m.id}
                      type="button"
                      role="option"
                      aria-selected={on}
                      className={
                        on ? "strip-chip strip-chip--on" : "strip-chip"
                      }
                      onClick={() => setMarketIndex(i)}
                    >
                      <span className="strip-chip__q" title={m.question}>
                        {label.length > 48 ? `${label.slice(0, 48)}…` : label}
                      </span>
                      <span className="strip-chip__px mono">
                        {p != null ? cents(p) : "—"}
                      </span>
                    </button>
                  );
                })}
              </div>
            </div>
          ) : null}

          {outcomes.length > 1 ? (
            <div
              className="terminal__strip"
              role="group"
              aria-label="Outcome"
            >
              <span className="terminal__strip-label">Outcome</span>
              <div className="terminal__strip-scroll">
                {outcomes.map((label, idx) => {
                  const p = market.outcomePrices[idx];
                  const on = outcomeIdx === idx;
                  return (
                    <button
                      key={label}
                      type="button"
                      className={on ? "strip-chip strip-chip--on" : "strip-chip"}
                      onClick={() => setOutcomeIdx(idx)}
                    >
                      <span className="strip-chip__q">{label}</span>
                      <span className="strip-chip__px mono">
                        {typeof p === "number" ? cents(p) : "—"}
                      </span>
                    </button>
                  );
                })}
              </div>
            </div>
          ) : null}

          {event.description ? (
            <details className="terminal__about">
              <summary>About</summary>
              <p>{event.description}</p>
            </details>
          ) : null}

          <p className="notice">
            <b>Prices are live, not advice.</b> An outcome at 70¢ prices a ~70%
            chance — it is not a prediction of what will happen, and it moves.
            {displayPrice != null ? (
              <>
                {" "}
                Current {outcomeLabel}: {percent(displayPrice)}.
              </>
            ) : null}
          </p>
        </div>

        <aside className="terminal__aside">
          <TradeTicket
            key={`${market.id}-${initialSide}-${preferredAsset ?? ""}`}
            market={market}
            preferredOutcome={outcomeLabel}
            preferredTokenID={tokenID ?? undefined}
            initialSide={initialSide}
            initialShares={initialShares}
            externalBook={top}
            onOutcomeChange={(label) => {
              const idx = outcomes.indexOf(label);
              if (idx >= 0) setOutcomeIdx(idx);
            }}
          />
        </aside>
      </div>
    </div>
  );
}
