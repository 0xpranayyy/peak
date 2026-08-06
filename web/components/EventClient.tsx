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

  return (
    <Suspense
      fallback={
        <div className="shell shell--wide terminal">
          <p className="empty">Loading ticket…</p>
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
    const live = event.markets.findIndex(
      (m) => m.active && !m.closed && m.clobTokenIds.length > 0
    );
    return live >= 0 ? live : 0;
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

      <header className="terminal__header">
        <div className="terminal__title-row">
          {event.imageUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img className="detail__art" src={event.imageUrl} alt="" />
          ) : null}
          <div className="terminal__title-block">
            <h1>{event.title}</h1>
            <div className="detail__meta">
              <span>{compactUsd(event.volume)} volume</span>
              <span>{compactUsd(event.liquidity)} liquidity</span>
              {event.volume24hr > 0 ? (
                <span>{compactUsd(event.volume24hr)} 24h</span>
              ) : null}
              {ends ? <span>{ends}</span> : null}
            </div>
          </div>
          <div className="terminal__header-actions">
            <WatchlistToggle eventId={event.id} />
          </div>
        </div>
      </header>

      {event.markets.length > 1 ? (
        <div className="terminal__markets" role="listbox" aria-label="Markets">
          {event.markets.map((m, i) => {
            const p = m.yesPrice;
            const on = i === marketIndex;
            return (
              <button
                key={m.id}
                type="button"
                role="option"
                aria-selected={on}
                className={on ? "outcome-sel outcome-sel--on" : "outcome-sel"}
                onClick={() => setMarketIndex(i)}
              >
                <span className="outcome-sel__q">
                  {m.question.length > 64
                    ? `${m.question.slice(0, 64)}…`
                    : m.question}
                </span>
                <span className="outcome-sel__price">
                  {p != null ? cents(p) : "—"}
                </span>
                {p != null ? (
                  <div className="bar outcome-sel__bar">
                    <i style={{ width: `${p * 100}%` }} />
                  </div>
                ) : null}
              </button>
            );
          })}
        </div>
      ) : null}

      {outcomes.length > 1 ? (
        <div className="terminal__outcomes" role="group" aria-label="Outcome">
          {outcomes.map((label, idx) => {
            const p = market.outcomePrices[idx];
            return (
              <button
                key={label}
                type="button"
                className={outcomeIdx === idx ? "chip chip--on" : "chip"}
                onClick={() => setOutcomeIdx(idx)}
              >
                {label}
                {typeof p === "number" ? ` · ${cents(p)}` : ""}
              </button>
            );
          })}
        </div>
      ) : null}

      <div className="terminal__grid">
        <div className="terminal__main">
          <PriceChart tokenID={tokenID} livePrice={displayPrice} />
          <OrderBookPanel tokenID={tokenID} onTopOfBook={onTopOfBook} />
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
  );
}
