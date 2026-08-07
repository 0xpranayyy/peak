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

/** Levels shown per side. The rest of the book is still counted in "Total". */
const DEPTH = 8;

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
    // `skipWhenHidden` applies to the poll, never the first fetch: a page opened
    // in a background tab is still a page, and bailing out of the initial load
    // left the book stuck on "Loading book…" until the tab was focused.
    const load = async (skipWhenHidden = false) => {
      if (skipWhenHidden && typeof document !== "undefined" && document.hidden) {
        return;
      }
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
    const timer = window.setInterval(() => void load(true), 5_000);
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

  // Asks display high→low (top of book nearest mid), bids high→low.
  //
  // Cumulative totals are computed over the *whole* book and only then trimmed
  // for display, so the "Total" column still means total resting size — the
  // trimming is a layout decision, not a change to the numbers. Deep books run
  // to 30+ levels a side; rendering all of them turned the panel into a page.
  const asks = useMemo(() => {
    if (!book) return [];
    const desc = [...book.asks].sort((a, b) => b.price - a.price);
    let running = 0;
    const rows = desc
      .slice()
      .reverse()
      .map((level) => {
        running += level.size;
        return { level, total: running };
      });
    rows.reverse();
    return rows.slice(-DEPTH);
  }, [book]);

  const bids = useMemo(() => {
    if (!book) return [];
    let running = 0;
    return book.bids
      .map((level) => {
        running += level.size;
        return { level, total: running };
      })
      .slice(0, DEPTH);
  }, [book]);

  // Scale the depth bars to the widest *visible* level. Scaling to the whole
  // book would flatten every rendered bar against one deep resting order well
  // outside the displayed range.
  const maxSize = useMemo(() => {
    let m = 0;
    for (const r of asks) m = Math.max(m, r.level.size);
    for (const r of bids) m = Math.max(m, r.level.size);
    return m || 1;
  }, [asks, bids]);

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
      ) : asks.length === 0 && bids.length === 0 ? (
        <p className="book__empty">No resting liquidity on this book.</p>
      ) : (
        <div className="book__body">
          <div className="book__side-label book__side-label--ask">Ask</div>
          <div className="book__side book__side--asks">
            {asks.length === 0 ? (
              <p className="book__empty book__empty--inline">No asks</p>
            ) : (
              asks.map(({ level, total }) => (
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
              ))
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
              bids.map(({ level, total }) => (
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
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
