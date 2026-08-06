"use client";

import { useEffect, useState } from "react";
import {
  DEFAULT_SORT,
  fetchEvents,
  type PeakEvent,
  type SortKey,
} from "@/lib/gamma";
import { categoryFromSlug } from "@/lib/categories";
import { MarketCard } from "@/components/MarketCard";
import { Filters } from "@/components/Filters";

const SORTS: SortKey[] = ["volume24hr", "volume", "liquidity", "endDate"];
const PAGE_SIZE = 24;

type Props = {
  tag?: string;
  sort?: string;
  page?: string;
};

/**
 * Markets feed loads in the browser on purpose.
 *
 * Gamma `/events?limit=24` is multi‑MB once nested markets are included.
 * Cloudflare Pages Functions routinely CPU-trip while `JSON.parse`-ing that
 * during SSR, which emptied the feed and cascaded into event-page failures.
 * The edge Worker already allows browser CORS (`*`), so the same client that
 * reads CLOB can read the feed without burning the SSR isolate.
 */
export function MarketsClient({ tag, sort, page: pageRaw }: Props) {
  const category = categoryFromSlug(tag);
  const activeTag = category?.slug;
  const activeSort: SortKey = SORTS.includes(sort as SortKey)
    ? (sort as SortKey)
    : DEFAULT_SORT;
  const page = Math.max(1, Number(pageRaw) || 1);
  const offset = (page - 1) * PAGE_SIZE;

  const [events, setEvents] = useState<PeakEvent[] | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setEvents(null);
    setError(false);
    (async () => {
      try {
        const nextEvents = await fetchEvents({
          limit: PAGE_SIZE,
          offset,
          sort: activeSort,
          tagSlug: activeTag,
        });
        if (cancelled) return;
        setEvents(nextEvents);
      } catch {
        if (cancelled) return;
        setEvents([]);
        setError(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [activeTag, activeSort, offset]);

  const hasMore = (events?.length ?? 0) >= PAGE_SIZE;
  const hasPrev = page > 1;

  return (
    <div className="shell page-body">
      <div className="page-head">
        <div>
          <h1>Markets</h1>
          <p>Live odds from Polymarket. Sign in to trade.</p>
        </div>
        <form className="search" action="/search" role="search">
          <input
            type="search"
            name="q"
            placeholder="Search markets"
            aria-label="Search markets"
          />
          <button type="submit">Search</button>
        </form>
      </div>

      <Filters activeTag={activeTag} activeSort={activeSort} />

      {events == null ? (
        <p className="empty">Loading markets…</p>
      ) : events.length === 0 ? (
        <p className="empty">
          {error
            ? "Markets are unavailable right now. Try again in a moment."
            : activeTag
              ? "No live markets in this category right now."
              : page > 1
                ? "No more markets on this page."
                : "Markets are unavailable right now. Try again in a moment."}
        </p>
      ) : (
        <div className="market-list">
          <div className="market-list__head" aria-hidden="true">
            <span>Market</span>
            <span>Chance</span>
          </div>
          {events.map((event) => (
            <MarketCard key={event.id} event={event} />
          ))}
        </div>
      )}

      {(hasPrev || hasMore) && events != null ? (
        <nav className="pager" aria-label="Markets pages">
          {hasPrev ? (
            <a
              className="btn"
              href={pageHref({ tag: activeTag, sort: activeSort, page: page - 1 })}
            >
              ← Previous
            </a>
          ) : (
            <span />
          )}
          <span className="pager__label">Page {page}</span>
          {hasMore ? (
            <a
              className="btn"
              href={pageHref({ tag: activeTag, sort: activeSort, page: page + 1 })}
            >
              Next →
            </a>
          ) : (
            <span />
          )}
        </nav>
      ) : null}
    </div>
  );
}

function pageHref(opts: {
  tag?: string;
  sort: SortKey;
  page: number;
}): string {
  const params = new URLSearchParams();
  if (opts.tag) params.set("tag", opts.tag);
  if (opts.sort !== DEFAULT_SORT) params.set("sort", opts.sort);
  if (opts.page > 1) params.set("page", String(opts.page));
  const q = params.toString();
  return q ? `/markets?${q}` : "/markets";
}
