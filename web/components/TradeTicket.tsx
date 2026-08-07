"use client";

import { useEffect, useMemo, useState } from "react";
import type { Market } from "@/lib/gamma";
import { usePeakSession } from "@/lib/session";
import {
  PeakApiError,
  fetchPortfolio,
  friendlyClientError,
  isMissingPrepareEndpoint,
  placeOrderDirect,
  prepareOrder,
  submitPreparedOrder,
} from "@/lib/api";
import { fetchTopOfBook, type TopOfBook } from "@/lib/clob";
import { cents } from "@/lib/format";
import { SignInSheet } from "@/components/SignInSheet";

type Side = "BUY" | "SELL";
type OrderKind = "market" | "limit";

const SELL_FRACTIONS = [
  { label: "25%", fraction: 0.25 },
  { label: "50%", fraction: 0.5 },
  { label: "75%", fraction: 0.75 },
  { label: "Max", fraction: 1 },
] as const;

/**
 * Format a share count for the input box.
 *
 * Rounds *down* to two decimals, never up: rounding a fraction of a holding
 * upward can land above the real balance and get the order rejected for
 * insufficient shares — which is exactly what a Max button is supposed to stop
 * happening. Trailing zeroes are dropped so the field reads "12" not "12.00".
 */
function trimShares(value: number): string {
  const floored = Math.floor(Math.max(0, value) * 100) / 100;
  return String(floored);
}

type Props = {
  market: Market;
  /** Prefer a specific outcome label when multi-outcome. */
  preferredOutcome?: string;
  /** Prefer a CLOB token id (from position deep-link). */
  preferredTokenID?: string;
  /** Pre-fill sell size when opening from a portfolio position. */
  initialShares?: number;
  /** Force sell when closing a position. */
  initialSide?: Side;
  /**
   * Live top-of-book from the terminal OrderBook panel.
   * When provided (including null while loading), skip the ticket's own poll.
   */
  externalBook?: TopOfBook | null;
  /** Sync outcome chips with the terminal selector. */
  onOutcomeChange?: (outcome: string) => void;
};

export function TradeTicket({
  market,
  preferredOutcome,
  preferredTokenID,
  initialShares,
  initialSide = "BUY",
  externalBook,
  onOutcomeChange,
}: Props) {
  const { authenticated, getToken, session, geo, syncing, runSetup } =
    usePeakSession();
  const [signInOpen, setSignInOpen] = useState(false);

  const outcomes = market.outcomes.length ? market.outcomes : ["Yes", "No"];
  const initialOutcome = (() => {
    if (preferredTokenID) {
      const idx = market.clobTokenIds.indexOf(preferredTokenID);
      if (idx >= 0 && outcomes[idx]) return outcomes[idx];
    }
    if (preferredOutcome && outcomes.includes(preferredOutcome)) {
      return preferredOutcome;
    }
    return outcomes[0];
  })();

  const [outcome, setOutcome] = useState(initialOutcome);
  const [side, setSide] = useState<Side>(initialSide);
  const [orderKind, setOrderKind] = useState<OrderKind>("limit");
  const [amountUsd, setAmountUsd] = useState("10");
  const [shares, setShares] = useState(
    initialShares != null && initialShares > 0 ? String(initialShares) : "10"
  );
  const [limitCents, setLimitCents] = useState(() => {
    const idx = Math.max(0, outcomes.indexOf(initialOutcome));
    const p = market.outcomePrices[idx] ?? market.yesPrice ?? 0.5;
    return String(Math.round(p * 100));
  });
  const [localBook, setLocalBook] = useState<TopOfBook | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  /**
   * Shares of the selected outcome this account actually holds.
   *
   * `null` means "not known" — signed out, still loading, or the lookup failed
   * — and is deliberately different from `0`, which means "known to hold
   * nothing". Only a known figure may drive a Max button or an oversell
   * warning; guessing at either would be worse than not offering them.
   */
  const [holding, setHolding] = useState<number | null>(null);

  const useExternal = externalBook !== undefined;
  const book = useExternal ? externalBook : localBook;

  const tokenID = useMemo(() => {
    const idx = outcomes.indexOf(outcome);
    return market.clobTokenIds[idx] ?? market.clobTokenIds[0] ?? null;
  }, [market.clobTokenIds, outcome, outcomes]);

  // Keep ticket outcome in sync with terminal selector / deep-links.
  useEffect(() => {
    if (preferredTokenID) {
      const idx = market.clobTokenIds.indexOf(preferredTokenID);
      if (idx >= 0 && outcomes[idx] && outcomes[idx] !== outcome) {
        setOutcome(outcomes[idx]);
        const p = market.outcomePrices[idx];
        if (typeof p === "number" && p > 0 && p < 1) {
          setLimitCents(String(Math.round(p * 100)));
        }
      }
      return;
    }
    if (preferredOutcome && outcomes.includes(preferredOutcome) && preferredOutcome !== outcome) {
      setOutcome(preferredOutcome);
      const idx = outcomes.indexOf(preferredOutcome);
      const p = market.outcomePrices[idx];
      if (typeof p === "number" && p > 0 && p < 1) {
        setLimitCents(String(Math.round(p * 100)));
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only react to external prefs
  }, [preferredOutcome, preferredTokenID, market.clobTokenIds, market.outcomePrices, outcomes]);

  useEffect(() => {
    if (useExternal) return;
    if (!tokenID || market.closed || !market.active) {
      setLocalBook(null);
      return;
    }
    let cancelled = false;
    // Same rule as OrderBookPanel: skip the poll while hidden, never the first
    // fetch — otherwise the ticket opens with no bid/ask to quote against.
    const load = async (skipWhenHidden = false) => {
      if (skipWhenHidden && typeof document !== "undefined" && document.hidden) {
        return;
      }
      const next = await fetchTopOfBook(tokenID);
      if (!cancelled) setLocalBook(next);
    };
    void load();
    const timer = window.setInterval(() => void load(true), 8_000);
    const onVisibility = () => {
      if (!document.hidden) void load();
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [tokenID, market.closed, market.active, useExternal]);

  /**
   * Look up the holding for the selected outcome.
   *
   * The portfolio is the only place that knows it — `initialShares` covers the
   * case where you arrived from the positions page, but someone who opens a
   * market directly and hits Sell has no idea what they own, and previously had
   * to guess or go and look it up.
   *
   * Only fetched on the sell side, and not polled: it is read once per outcome,
   * and a fill refreshes it. Buyers never need it, and making every event page
   * pull a full portfolio for a button they will not see is exactly the kind of
   * eager loading this client is trying not to do.
   */
  useEffect(() => {
    if (!authenticated || !tokenID || side !== "SELL") {
      setHolding(null);
      return;
    }
    const controller = new AbortController();
    (async () => {
      try {
        const token = await getToken();
        if (!token || controller.signal.aborted) return;
        const snapshot = await fetchPortfolio(token);
        if (controller.signal.aborted) return;
        const match = snapshot.positions.find((p) => p.asset === tokenID);
        setHolding(match ? match.size : 0);
      } catch {
        // Leave it unknown rather than claiming zero — a failed lookup must not
        // render as "you hold nothing".
        if (!controller.signal.aborted) setHolding(null);
      }
    })();
    return () => controller.abort();
  }, [authenticated, tokenID, side, getToken, message]);

  const quotePrice = useMemo(() => {
    if (orderKind === "limit") {
      const n = Number(limitCents);
      if (!Number.isFinite(n)) return null;
      const p = n / 100;
      return p > 0 && p < 1 ? Math.round(p * 1000) / 1000 : null;
    }
    // Market: require a live top-of-book quote — never invent 0.5.
    if (side === "BUY") return book?.ask ?? null;
    return book?.bid ?? null;
  }, [orderKind, limitCents, side, book]);

  const marketNeedsBook = orderKind === "market" && quotePrice == null;

  const size = useMemo(() => {
    if (!quotePrice) return null;
    if (side === "SELL") {
      const s = Number(shares);
      if (!Number.isFinite(s) || s <= 0) return null;
      return Math.round(s * 100) / 100;
    }
    const usd = Number(amountUsd);
    if (!Number.isFinite(usd) || usd <= 0) return null;
    return Math.round((usd / quotePrice) * 100) / 100;
  }, [side, shares, amountUsd, quotePrice]);

  /**
   * Only flag an oversell when the holding is actually known. An unknown
   * balance must not produce a warning — the backend's `insufficient_shares`
   * remains the authority either way; this just saves the round trip.
   */
  const oversell =
    side === "SELL" &&
    holding != null &&
    Number(shares) > 0 &&
    Number(shares) > holding;

  /** What this sell is worth at the quoted price, when both are known. */
  const sellProceeds =
    side === "SELL" && quotePrice != null && size != null
      ? size * quotePrice
      : null;

  /**
   * The sellable maximum, as the exact string the input will receive.
   *
   * Label and action share this one value on purpose. Formatting the label
   * separately let them disagree — `toFixed(2)` rounds up where `trimShares`
   * floors, so a 0.005 holding advertised "Max 0.01" and then filled in 0.
   */
  const maxShares = holding != null && holding > 0 ? trimShares(holding) : null;
  const canMax = maxShares != null && Number(maxShares) > 0;

  const apiOrderType = useMemo(() => {
    if (orderKind === "limit") return "GTC";
    // Market sells are FAK (partial fill OK); buys stay FOK — matches iOS.
    return side === "SELL" ? "FAK" : "FOK";
  }, [orderKind, side]);

  // Geo is submit-time only — never grey out the ticket. Unknown / loading
  // stays open; API + CLOB still enforce. Matches “no geo theater” on browse.
  const geoBlocksBuy = geo?.status === "blocked" || geo?.status === "close_only";
  const geoBlocksSell = geo?.status === "blocked";
  const geoBlocked = (side === "BUY" && geoBlocksBuy) || (side === "SELL" && geoBlocksSell);

  function applyQuoteToLimit() {
    const p = side === "BUY" ? book?.ask ?? book?.mid : book?.bid ?? book?.mid;
    if (p != null) setLimitCents(String(Math.round(p * 100)));
  }

  async function onSubmit(event: React.FormEvent) {
    event.preventDefault();
    setMessage(null);
    setError(null);

    if (!authenticated) {
      setSignInOpen(true);
      return;
    }
    if (!tokenID) {
      setError("This market has no tradeable token ids yet.");
      return;
    }
    if (marketNeedsBook) {
      setError("Waiting for a live bid/ask. Try again in a moment.");
      return;
    }
    if (!quotePrice || !size) {
      setError(
        side === "SELL"
          ? "Enter a valid share size and a price between 1¢ and 99¢."
          : "Enter a valid USD amount and a price between 1¢ and 99¢."
      );
      return;
    }
    if (oversell) {
      setError(
        `You hold ${maxShares} ${outcome}. Reduce the size, or use Max.`
      );
      return;
    }
    if (geoBlocked) {
      setError(
        geo?.status === "close_only"
          ? "New positions aren’t available here."
          : "Trading isn’t available here."
      );
      return;
    }

    setBusy(true);
    try {
      if (session?.needsDeploy) {
        await runSetup();
      }
      const token = await getToken();
      if (!token) throw new Error("Sign in again to place this order.");

      const order = {
        tokenID,
        price: Math.round(quotePrice * 1000) / 1000,
        size,
        side,
        amount:
          side === "BUY" && orderKind === "market"
            ? Math.round(Number(amountUsd) * 100) / 100
            : side === "BUY"
              ? Math.round(Number(amountUsd) * 100) / 100
              : undefined,
        orderType: apiOrderType,
        negRisk: market.negRisk,
      };

      try {
        const prepared = await prepareOrder(token, order);
        const result = await submitPreparedOrder(prepared);
        const orderId =
          (typeof result.orderID === "string" && result.orderID) ||
          (typeof result.id === "string" && result.id) ||
          null;
        setMessage(
          orderId
            ? `Order submitted · ${size} shares @ ${cents(quotePrice)} · ${orderId.slice(0, 10)}…`
            : `Order submitted · ${size} shares @ ${cents(quotePrice)}`
        );
      } catch (err) {
        if (isMissingPrepareEndpoint(err)) {
          const result = await placeOrderDirect(token, order);
          if (result.success === false) {
            throw new PeakApiError(
              String(result.error ?? result.errorMsg ?? "Order failed"),
              400,
              typeof result.code === "string" ? result.code : null,
              result
            );
          }
          setMessage(`Order placed · ${size} shares @ ${cents(quotePrice)}`);
          return;
        }
        throw err;
      }
    } catch (err) {
      setError(friendlyClientError(err));
    } finally {
      setBusy(false);
    }
  }

  if (market.closed || !market.active) {
    return (
      <div className="ticket ticket--closed">
        <p>This market is closed. Trading is unavailable.</p>
      </div>
    );
  }

  return (
    <form className="ticket" onSubmit={onSubmit}>
      <div className="ticket__head">
        <h2>Trade</h2>
        {outcome ? (
          <p className="ticket__hint">
            {outcome}
            {quotePrice != null ? ` · ${cents(quotePrice)}` : ""}
          </p>
        ) : null}
      </div>

      <div className="ticket__sides" role="group" aria-label="Side">
        <button
          type="button"
          className={side === "BUY" ? "seg seg--on seg--buy" : "seg"}
          onClick={() => setSide("BUY")}
        >
          Buy
        </button>
        <button
          type="button"
          className={side === "SELL" ? "seg seg--on seg--sell" : "seg"}
          onClick={() => setSide("SELL")}
        >
          Sell
        </button>
      </div>

      <div className="ticket__sides" role="group" aria-label="Order type">
        <button
          type="button"
          className={orderKind === "limit" ? "seg seg--on" : "seg"}
          onClick={() => setOrderKind("limit")}
        >
          Limit
        </button>
        <button
          type="button"
          className={orderKind === "market" ? "seg seg--on" : "seg"}
          onClick={() => setOrderKind("market")}
        >
          Market
        </button>
      </div>

      {outcomes.length > 1 ? (
        <div className="ticket__outcomes" role="group" aria-label="Outcome">
          {outcomes.map((label, idx) => {
            const p = market.outcomePrices[idx];
            return (
              <button
                key={label}
                type="button"
                className={outcome === label ? "chip chip--on" : "chip"}
                onClick={() => {
                  setOutcome(label);
                  onOutcomeChange?.(label);
                  if (typeof p === "number" && p > 0 && p < 1) {
                    setLimitCents(String(Math.round(p * 100)));
                  }
                }}
              >
                {label}
                {typeof p === "number" ? ` · ${cents(p)}` : ""}
              </button>
            );
          })}
        </div>
      ) : null}

      <div className="ticket__book" aria-live="polite">
        <span>
          Bid <b>{book?.bid != null ? cents(book.bid) : "—"}</b>
        </span>
        <span>
          Ask <b>{book?.ask != null ? cents(book.ask) : "—"}</b>
        </span>
        <span>
          Spread{" "}
          <b>
            {book?.spread != null ? `${Math.round(book.spread * 100)}¢` : "—"}
          </b>
        </span>
      </div>

      {side === "SELL" ? (
        <label className="field">
          <span>
            Shares
            {canMax ? (
              <button
                type="button"
                className="field__link"
                onClick={() => setShares(maxShares)}
              >
                Max {maxShares}
              </button>
            ) : null}
          </span>
          <input
            inputMode="decimal"
            value={shares}
            onChange={(e) => setShares(e.target.value)}
            placeholder="10"
          />
        </label>
      ) : (
        <label className="field">
          <span>Amount (USD)</span>
          <input
            inputMode="decimal"
            value={amountUsd}
            onChange={(e) => setAmountUsd(e.target.value)}
            placeholder="10"
          />
        </label>
      )}

      {/* Selling a known holding is measured in fractions of it — "half my
          position", not "25 shares". Fixed share counts only make sense when
          nobody knows what you own, so they stay as the fallback. */}
      <div className="ticket__presets" role="group" aria-label="Size presets">
        {side === "SELL" && canMax && holding != null
          ? SELL_FRACTIONS.map(({ label, fraction }) => {
              const target =
                fraction === 1 ? maxShares : trimShares(holding * fraction);
              return (
                <button
                  key={label}
                  type="button"
                  className={shares === target ? "preset preset--on" : "preset"}
                  onClick={() => setShares(target)}
                >
                  {label}
                </button>
              );
            })
          : (side === "SELL" ? [5, 10, 25, 50, 100] : [5, 10, 25, 50, 100]).map(
              (n) => {
                const active =
                  side === "SELL"
                    ? Number(shares) === n
                    : Number(amountUsd) === n;
                return (
                  <button
                    key={n}
                    type="button"
                    className={active ? "preset preset--on" : "preset"}
                    onClick={() => {
                      if (side === "SELL") setShares(String(n));
                      else setAmountUsd(String(n));
                    }}
                  >
                    {side === "SELL" ? n : `$${n}`}
                  </button>
                );
              }
            )}
      </div>

      {side === "SELL" && holding != null ? (
        <p className="ticket__holding">
          {canMax ? (
            <>
              You hold <b>{maxShares}</b> {outcome}
              {sellProceeds != null ? (
                <>
                  {" · "}selling {shares || "0"} ≈ <b>${sellProceeds.toFixed(2)}</b>
                </>
              ) : null}
            </>
          ) : (
            <>No {outcome} shares in this account to sell.</>
          )}
        </p>
      ) : null}

      {oversell ? (
        <p className="ticket__status ticket__status--warn" role="alert">
          That is more than you hold. Max is {maxShares}.
        </p>
      ) : null}

      {orderKind === "limit" ? (
        <label className="field">
          <span>
            Limit price (¢){" "}
            {book?.bid != null || book?.ask != null ? (
              <button type="button" className="field__link" onClick={applyQuoteToLimit}>
                Use {side === "BUY" ? "ask" : "bid"}
              </button>
            ) : null}
          </span>
          <input
            inputMode="numeric"
            value={limitCents}
            onChange={(e) => setLimitCents(e.target.value)}
            placeholder="50"
          />
        </label>
      ) : (
        <p className="ticket__hint">
          Market {side === "BUY" ? "buy" : "sell"} · fills at best{" "}
          {side === "BUY" ? "ask" : "bid"}
          {quotePrice != null ? ` (~${cents(quotePrice)})` : ""}.{" "}
          {side === "SELL" ? "Partial fills allowed (FAK)." : "All-or-nothing (FOK)."}
        </p>
      )}

      <div className="ticket__meta">
        <span>
          {side === "SELL" ? (
            <>
              Est. proceeds{" "}
              <b>
                {size != null && quotePrice != null
                  ? `$${(size * quotePrice).toFixed(2)}`
                  : "—"}
              </b>
            </>
          ) : (
            <>
              Est. shares <b>{size != null ? size.toFixed(2) : "—"}</b>
            </>
          )}
        </span>
        <span>
          Type <b>{apiOrderType}</b>
        </span>
      </div>

      {!authenticated ? (
        <button
          type="button"
          className="btn btn--primary ticket__submit"
          onClick={() => setSignInOpen(true)}
        >
          Sign in to trade
        </button>
      ) : (
        <button
          type="submit"
          className="btn btn--primary ticket__submit"
          disabled={busy || syncing || !tokenID || marketNeedsBook || oversell}
        >
          {busy ? "Submitting…" : `${side === "BUY" ? "Buy" : "Sell"} ${outcome}`}
        </button>
      )}

      {marketNeedsBook ? (
        <p className="ticket__status ticket__status--warn">
          Waiting for a live {side === "BUY" ? "ask" : "bid"} before market orders.
          Switch to Limit to place without a quote.
        </p>
      ) : null}
      {error ? <p className="ticket__status ticket__status--err">{error}</p> : null}
      {message ? (
        <p className="ticket__status ticket__status--ok">
          {message}{" "}
          <a href="/positions">View positions</a>
        </p>
      ) : null}

      <SignInSheet
        open={signInOpen}
        onClose={() => setSignInOpen(false)}
        reason="trade"
      />
    </form>
  );
}
