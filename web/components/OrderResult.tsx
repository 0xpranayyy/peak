"use client";

import { useEffect, useRef } from "react";
import { createPortal } from "react-dom";
import type { OrderOutcome } from "@/lib/api";
import { cents } from "@/lib/format";

export type OrderReceipt = {
  outcome: OrderOutcome;
  side: "BUY" | "SELL";
  /** The outcome name traded, e.g. "Yes" or "No change". */
  outcomeLabel: string;
  marketTitle: string;
  /** Price the order was placed at. */
  price: number;
  /** True for a limit order that can rest on the book. */
  isLimit: boolean;
};

/**
 * What happened to an order, said plainly.
 *
 * The ticket used to report every result as one line of small text reading
 * "Order submitted" — the same sentence whether the order filled, partially
 * filled, or is sitting unmatched on the book indefinitely. On a phone that is
 * easy to miss entirely, and it left the one question a trader actually has
 * ("did that go through?") unanswered.
 *
 * The four states are kept distinct because they mean genuinely different
 * things to whoever just pressed the button. "Resting" in particular is not a
 * success message: nothing has been bought.
 */
export function OrderResult({
  receipt,
  onDismiss,
}: {
  receipt: OrderReceipt | null;
  onDismiss: () => void;
}) {
  const panelRef = useRef<HTMLDivElement>(null);
  const restoreFocus = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!receipt) return;
    restoreFocus.current = document.activeElement as HTMLElement | null;
    panelRef.current?.focus();

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        onDismiss();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previousOverflow;
      restoreFocus.current?.focus?.();
    };
  }, [receipt, onDismiss]);

  if (!receipt) return null;
  if (typeof document === "undefined") return null;

  const { outcome, side, outcomeLabel, marketTitle, price, isLimit } = receipt;
  const verb = side === "BUY" ? "bought" : "sold";
  const shares = outcome.filledSize ?? outcome.requestedSize;
  const value = shares * price;

  const copy = {
    filled: {
      tone: "ok" as const,
      title: side === "BUY" ? "Bought" : "Sold",
      body: `${fmt(shares)} ${outcomeLabel} at ${cents(price)}.`,
    },
    partial: {
      tone: "warn" as const,
      title: "Partially filled",
      body:
        outcome.filledSize != null
          ? `${fmt(outcome.filledSize)} of ${fmt(outcome.requestedSize)} ${verb} at ${cents(price)}. The rest did not fill.`
          : `Part of this order filled at ${cents(price)}.`,
    },
    resting: {
      tone: "info" as const,
      title: "Order is on the book",
      body: isLimit
        ? `Nothing has ${verb === "bought" ? "been bought" : "sold"} yet. ${fmt(outcome.requestedSize)} ${outcomeLabel} will fill if the market reaches ${cents(price)}.`
        : `This order did not match and is resting at ${cents(price)}.`,
    },
    submitted: {
      tone: "info" as const,
      title: "Order submitted",
      body: `${fmt(outcome.requestedSize)} ${outcomeLabel} at ${cents(price)}. Check Positions for the fill.`,
    },
  }[outcome.kind];

  return createPortal(
    <div
      className="sheet-scrim"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onDismiss();
      }}
    >
      <div
        className={`sheet receipt receipt--${copy.tone}`}
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="receipt-title"
        ref={panelRef}
        tabIndex={-1}
      >
        <div className="receipt__badge" aria-hidden="true">
          {copy.tone === "ok" ? <CheckIcon /> : null}
          {copy.tone === "warn" ? <HalfIcon /> : null}
          {copy.tone === "info" ? <ClockIcon /> : null}
        </div>

        <h2 id="receipt-title" className="receipt__title">
          {copy.title}
        </h2>
        <p className="receipt__body">{copy.body}</p>

        <dl className="receipt__rows">
          <div>
            <dt>Market</dt>
            <dd className="receipt__market">{marketTitle}</dd>
          </div>
          <div>
            <dt>{outcome.kind === "resting" ? "Limit price" : "Price"}</dt>
            <dd className="mono">{cents(price)}</dd>
          </div>
          {outcome.filledSize != null && outcome.kind !== "resting" ? (
            <div>
              <dt>{side === "BUY" ? "Cost" : "Proceeds"}</dt>
              <dd className="mono">${value.toFixed(2)}</dd>
            </div>
          ) : null}
          {outcome.orderId ? (
            <div>
              <dt>Order</dt>
              <dd className="mono receipt__id">{outcome.orderId}</dd>
            </div>
          ) : null}
        </dl>

        <div className="receipt__actions">
          <a className="btn btn--primary" href="/positions">
            View positions
          </a>
          <button type="button" className="btn" onClick={onDismiss}>
            {outcome.kind === "resting" ? "Done" : "Trade again"}
          </button>
        </div>
      </div>
    </div>,
    document.body
  );
}

/** Whole numbers stay whole; fractions keep two places. */
function fmt(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(2);
}

function CheckIcon() {
  return (
    <svg viewBox="0 0 24 24" width="26" height="26" fill="none" aria-hidden="true">
      <path
        d="M4.5 12.5l5 5 10-11"
        stroke="currentColor"
        strokeWidth="2.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function HalfIcon() {
  return (
    <svg viewBox="0 0 24 24" width="26" height="26" fill="none" aria-hidden="true">
      <circle cx="12" cy="12" r="8.6" stroke="currentColor" strokeWidth="2.2" />
      <path d="M12 3.4a8.6 8.6 0 0 1 0 17.2Z" fill="currentColor" />
    </svg>
  );
}

function ClockIcon() {
  return (
    <svg viewBox="0 0 24 24" width="26" height="26" fill="none" aria-hidden="true">
      <circle cx="12" cy="12" r="8.6" stroke="currentColor" strokeWidth="2.2" />
      <path
        d="M12 7.2v5.2l3.4 2"
        stroke="currentColor"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
