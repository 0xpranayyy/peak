"use client";

import { useMemo, useState } from "react";
import type { Market } from "@/lib/gamma";
import { usePeakSession } from "@/lib/session";
import {
  PeakApiError,
  placeOrderDirect,
  prepareOrder,
  submitPreparedOrder,
} from "@/lib/api";
import { cents } from "@/lib/format";

type Side = "BUY" | "SELL";

type Props = {
  market: Market;
  /** Prefer a specific outcome label when multi-outcome. */
  preferredOutcome?: string;
};

export function TradeTicket({ market, preferredOutcome }: Props) {
  const { authenticated, login, getToken, session, geo, syncing, runSetup } =
    usePeakSession();

  const outcomes = market.outcomes.length ? market.outcomes : ["Yes", "No"];
  const initialOutcome =
    preferredOutcome && outcomes.includes(preferredOutcome)
      ? preferredOutcome
      : outcomes[0];

  const [outcome, setOutcome] = useState(initialOutcome);
  const [side, setSide] = useState<Side>("BUY");
  const [amountUsd, setAmountUsd] = useState("10");
  const [limitCents, setLimitCents] = useState(() => {
    const idx = Math.max(0, outcomes.indexOf(initialOutcome));
    const p = market.outcomePrices[idx] ?? market.yesPrice ?? 0.5;
    return String(Math.round(p * 100));
  });
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const tokenID = useMemo(() => {
    const idx = outcomes.indexOf(outcome);
    return market.clobTokenIds[idx] ?? market.clobTokenIds[0] ?? null;
  }, [market.clobTokenIds, outcome, outcomes]);

  const price = useMemo(() => {
    const n = Number(limitCents);
    if (!Number.isFinite(n)) return null;
    const p = n / 100;
    return p > 0 && p < 1 ? Math.round(p * 1000) / 1000 : null;
  }, [limitCents]);

  const size = useMemo(() => {
    const usd = Number(amountUsd);
    if (!price || !Number.isFinite(usd) || usd <= 0) return null;
    return Math.round((usd / price) * 100) / 100;
  }, [amountUsd, price]);

  const geoBlocksBuy = geo?.status === "blocked" || geo?.status === "close_only";
  const geoBlocksSell = geo?.status === "blocked";
  const geoBlocked = (side === "BUY" && geoBlocksBuy) || (side === "SELL" && geoBlocksSell);

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
    if (!price || !size) {
      setError("Enter a valid USD amount and a price between 1¢ and 99¢.");
      return;
    }
    if (geoBlocked) {
      setError(
        geo?.status === "close_only"
          ? "New positions aren’t available in your region."
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
        price,
        size,
        side,
        amount: side === "BUY" ? Math.round(Number(amountUsd) * 100) / 100 : undefined,
        orderType: "GTC",
        negRisk: market.negRisk,
      };

      try {
        const prepared = await prepareOrder(token, order);
        const result = await submitPreparedOrder(prepared);
        const ok = result.success !== false;
        setMessage(
          ok
            ? `Order ${side === "BUY" ? "bought" : "sold"} · ${size} shares @ ${cents(price)}`
            : typeof result.errorMsg === "string"
              ? result.errorMsg
              : "Order submitted."
        );
      } catch (err) {
        if (err instanceof PeakApiError && err.status === 404) {
          const result = await placeOrderDirect(token, order);
          setMessage(
            result.success === false
              ? String(result.error ?? "Order failed")
              : `Order placed · ${size} shares @ ${cents(price)}`
          );
          return;
        }
        throw err;
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Order failed.");
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
          Peak signs on the server; your browser submits so eligibility follows your IP.
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

      <label className="field">
        <span>Amount (USD)</span>
        <input
          inputMode="decimal"
          value={amountUsd}
          onChange={(e) => setAmountUsd(e.target.value)}
          placeholder="10"
        />
      </label>

      <label className="field">
        <span>Limit price (¢)</span>
        <input
          inputMode="numeric"
          value={limitCents}
          onChange={(e) => setLimitCents(e.target.value)}
          placeholder="50"
        />
      </label>

      <div className="ticket__meta">
        <span>
          Est. shares{" "}
          <b>{size != null ? size.toFixed(2) : "—"}</b>
        </span>
        <span>
          Token{" "}
          <b className="mono">
            {tokenID ? `${tokenID.slice(0, 8)}…` : "missing"}
          </b>
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
          disabled={busy || syncing || geoBlocked || !tokenID}
        >
          {busy ? "Submitting…" : `${side === "BUY" ? "Buy" : "Sell"} ${outcome}`}
        </button>
      )}

      {geoBlocked ? (
        <p className="ticket__status ticket__status--warn">
          {geo?.status === "close_only"
            ? "New buys are blocked in your region."
            : "Trading is blocked in your region."}
        </p>
      ) : null}
      {error ? <p className="ticket__status ticket__status--err">{error}</p> : null}
      {message ? <p className="ticket__status ticket__status--ok">{message}</p> : null}
    </form>
  );
}
