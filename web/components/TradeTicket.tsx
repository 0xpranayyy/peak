"use client";

import { useEffect, useMemo, useState } from "react";
import type { Market } from "@/lib/gamma";
import { usePeakSession } from "@/lib/session";
import {
  PeakApiError,
  friendlyClientError,
  isMissingPrepareEndpoint,
  placeOrderDirect,
  prepareOrder,
  submitPreparedOrder,
} from "@/lib/api";
import { fetchTopOfBook, type TopOfBook } from "@/lib/clob";
import { cents } from "@/lib/format";

type Side = "BUY" | "SELL";
type OrderKind = "market" | "limit";

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
};

export function TradeTicket({
  market,
  preferredOutcome,
  preferredTokenID,
  initialShares,
  initialSide = "BUY",
}: Props) {
  const { authenticated, login, getToken, session, geo, syncing, runSetup } =
    usePeakSession();

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
  const [book, setBook] = useState<TopOfBook | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const tokenID = useMemo(() => {
    const idx = outcomes.indexOf(outcome);
    return market.clobTokenIds[idx] ?? market.clobTokenIds[0] ?? null;
  }, [market.clobTokenIds, outcome, outcomes]);

  useEffect(() => {
    if (!tokenID || market.closed || !market.active) {
      setBook(null);
      return;
    }
    let cancelled = false;
    const load = async () => {
      if (typeof document !== "undefined" && document.hidden) return;
      const next = await fetchTopOfBook(tokenID);
      if (!cancelled) setBook(next);
    };
    void load();
    const timer = window.setInterval(() => void load(), 8_000);
    const onVisibility = () => {
      if (!document.hidden) void load();
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [tokenID, market.closed, market.active]);

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

  const apiOrderType = useMemo(() => {
    if (orderKind === "limit") return "GTC";
    // Market sells are FAK (partial fill OK); buys stay FOK — matches iOS.
    return side === "SELL" ? "FAK" : "FOK";
  }, [orderKind, side]);

  // Unknown / missing geo: block new buys (fail closed); sells stay until CLOB refuses.
  const geoBlocksBuy =
    geo == null ||
    geo.status === "blocked" ||
    geo.status === "close_only" ||
    geo.status === "unknown";
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
      login();
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
    if (geoBlocked) {
      setError(
        geo?.status === "close_only"
          ? "New positions aren’t available in your region."
          : geo?.status === "unknown"
            ? "Couldn’t confirm your region yet. New buys are paused until geo loads."
            : "Trading isn’t available in your region."
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
        <p className="ticket__hint">
          Peak signs on the server; your browser posts to CLOB so eligibility
          follows your IP.
        </p>
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
          className={orderKind === "market" ? "seg seg--on" : "seg"}
          onClick={() => setOrderKind("market")}
        >
          Market
        </button>
        <button
          type="button"
          className={orderKind === "limit" ? "seg seg--on" : "seg"}
          onClick={() => setOrderKind("limit")}
        >
          Limit
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
          <span>Shares</span>
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
        <button type="button" className="btn btn--primary ticket__submit" onClick={login}>
          Sign in to trade
        </button>
      ) : (
        <button
          type="submit"
          className="btn btn--primary ticket__submit"
          disabled={busy || syncing || geoBlocked || !tokenID || marketNeedsBook}
        >
          {busy ? "Submitting…" : `${side === "BUY" ? "Buy" : "Sell"} ${outcome}`}
        </button>
      )}

      {geoBlocked ? (
        <p className="ticket__status ticket__status--warn">
          {geo == null
            ? "Checking your region…"
            : geo.status === "close_only"
              ? "New buys are blocked in your region. You can still sell to close."
              : geo.status === "unknown"
                ? "Couldn’t confirm your region. New buys are paused; sells may still work."
                : "Trading is blocked in your region. You can still browse markets."}
        </p>
      ) : null}
      {marketNeedsBook && !geoBlocked ? (
        <p className="ticket__status ticket__status--warn">
          Waiting for a live {side === "BUY" ? "ask" : "bid"} before market orders.
        </p>
      ) : null}
      {error ? <p className="ticket__status ticket__status--err">{error}</p> : null}
      {message ? (
        <p className="ticket__status ticket__status--ok">
          {message}{" "}
          <a href="/positions">View positions</a>
        </p>
      ) : null}
    </form>
  );
}
