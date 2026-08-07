"use client";

import { useEffect, useMemo, useState } from "react";
import { fetchOrderBook, type OrderBook } from "@/lib/clob";
import { cents } from "@/lib/format";

type Props = {
  tokenID: string | null;
  /** Notify parent when top-of-book updates (ticket quotes). */
  onTopOfBook?: (book: {
    bid: number | null;
    ask: number | null;
    mid: number | null;
    spread: number | null;
  }) => void;
};

function formatSize(size: number): string {
  if (size >= 1_000_000) return `${(size / 1_000_000).toFixed(1)}M`;
  if (size >= 1_000) return `${(size / 1_000).toFixed(1)}K`;
  if (size >= 100) return size.toFixed(0);
  return size.toFixed(1);
}

/**
 * CLOB depth — real bids/asks from edge `/clob/book`. No mock levels.
 */
export function OrderBookPanel({ tokenID, onTopOfBook }: Props) {
  const [book, setBook] = useState<OrderBook | null>(null);

  useEffect(() => {
    if (!tokenID) {
      setBook(null);
      onTopOfBook?.({ bid: null, ask: null, mid: null, spread: null });
      return;
    }
    let cancelled = false;
    const load = async () => {
      if (typeof document !== "undefined" && document.hidden) return;
      const next = await fetchOrderBook(tokenID);
      if (cancelled) return;
      setBook(next);
      onTopOfBook?.({
        bid: next.bid,
        ask: next.ask,
        mid: next.mid,
        spread: next.spread,
      });
    };
    void load();
    const timer = window.setInterval(() => void load(), 5_000);
    const onVisibility = () => {
      if (!document.hidden) void load();
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [tokenID, onTopOfBook]);

  const maxSize = useMemo(() => {
    if (!book) return 1;
    let m = 0;
    for (const l of book.bids) m = Math.max(m, l.size);
    for (const l of book.asks) m = Math.max(m, l.size);
    return m || 1;
  }, [book]);

  // Asks display high→low (top of book nearest mid), bids high→low.
  const asksDesc = useMemo(
    () => (book ? [...book.asks].sort((a, b) => b.price - a.price) : []),
    [book]
  );
  const bids = book?.bids ?? [];

  return (
    <div className="book">
      <div className="book__head">
        <span className="book__label">Order book</span>
        <div className="book__stats mono">
          <span>
            Mid{" "}
            <b>{book?.mid != null ? cents(book.mid) : "—"}</b>
          </span>
          <span>
            Spread{" "}
            <b>
              {book?.spread != null
                ? `${Math.round(book.spread * 1000) / 10}¢`
                : "—"}
            </b>
          </span>
        </div>
      </div>

      <div className="book__cols" aria-hidden="true">
        <span>Price</span>
        <span>Size</span>
        <span>Total</span>
      </div>

      {!tokenID ? (
        <p className="book__empty">Select an outcome to see the book.</p>
      ) : book == null ? (
        <p className="book__empty">Loading book…</p>
      ) : asksDesc.length === 0 && bids.length === 0 ? (
        <p className="book__empty">No resting liquidity on this book.</p>
      ) : (
        <div className="book__body">
          <div className="book__side-label book__side-label--ask">Ask</div>
          <div className="book__side book__side--asks">
            {asksDesc.length === 0 ? (
              <p className="book__empty book__empty--inline">No asks</p>
            ) : (
              asksDesc.map((level, i) => {
                const total = asksDesc
                  .slice(i)
                  .reduce((s, l) => s + l.size, 0);
                return (
                  <div
                    key={`a-${level.price}`}
                    className="book__row book__row--ask"
                  >
                    <i
                      className="book__depth"
                      style={{ width: `${(level.size / maxSize) * 100}%` }}
                    />
                    <span className="book__price">{cents(level.price)}</span>
                    <span className="book__size mono">
                      {formatSize(level.size)}
                    </span>
                    <span className="book__total mono">{formatSize(total)}</span>
                  </div>
                );
              })
            )}
          </div>

          <div className="book__spread mono">
            <span>
              Bid {book.bid != null ? cents(book.bid) : "—"}
              {" · "}
              Ask {book.ask != null ? cents(book.ask) : "—"}
            </span>
          </div>

          <div className="book__side-label book__side-label--bid">Bid</div>
          <div className="book__side book__side--bids">
            {bids.length === 0 ? (
              <p className="book__empty book__empty--inline">No bids</p>
            ) : (
              bids.map((level, i) => {
                const total = bids.slice(0, i + 1).reduce((s, l) => s + l.size, 0);
                return (
                  <div
                    key={`b-${level.price}`}
                    className="book__row book__row--bid"
                  >
                    <i
                      className="book__depth"
                      style={{ width: `${(level.size / maxSize) * 100}%` }}
                    />
                    <span className="book__price">{cents(level.price)}</span>
                    <span className="book__size mono">
                      {formatSize(level.size)}
                    </span>
                    <span className="book__total mono">{formatSize(total)}</span>
                  </div>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
}
