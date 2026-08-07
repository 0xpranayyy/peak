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
import { WelcomePanel } from "@/components/WelcomePanel";

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
  const countLabel =
    events == null
      ? null
      : events.length === 0
        ? null
        : `${events.length}${hasMore ? "+" : ""} markets`;

  return (
    <div className="shell page-body">
      <WelcomePanel />

      <div className="page-head page-head--markets">
        <div>
          <h1>Markets</h1>
          <p>Browse live prediction markets. Open a row to trade.</p>
        </div>
        {countLabel ? (
          <span className="result-meta result-meta--inline">{countLabel}</span>
        ) : null}
      </div>

      <div className="browse-bar">
        <form className="search search--bar" action="/search" role="search">
          <input
            type="search"
            name="q"
            placeholder="Search markets…"
            aria-label="Search markets"
            autoComplete="off"
          />
          <button type="submit">Search</button>
        </form>
        <Filters activeTag={activeTag} activeSort={activeSort} />
      </div>

      {events == null ? (
        <div className="market-list" aria-busy="true" aria-label="Loading markets">
          <div className="market-list__head" aria-hidden="true">
            <span>Market</span>
            <span>Vol</span>
            <span>24h</span>
            <span>Chance</span>
          </div>
          {Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="market-row market-row--skeleton" aria-hidden="true">
              <div className="skel skel--thumb" />
              <div className="skel skel--title" />
              <div className="skel skel--num" />
              <div className="skel skel--num" />
              <div className="skel skel--price" />
            </div>
          ))}
        </div>
      ) : events.length === 0 ? (
        <div className="empty-state">
          <p className="empty-state__title">
            {error
              ? "Markets unavailable"
              : activeTag
                ? "No markets in this category"
                : page > 1
                  ? "No more markets"
                  : "Markets unavailable"}
          </p>
          <p className="empty-state__body">
            {error
              ? "The feed didn’t load. Try again in a moment."
              : activeTag
                ? "Try All, or another category."
                : page > 1
                  ? "Go back to the previous page."
                  : "The feed didn’t load. Try again in a moment."}
          </p>
          {activeTag || page > 1 ? (
            <a className="btn" href="/markets">
              Reset filters
            </a>
          ) : null}
        </div>
      ) : (
        <div className="market-list">
          <div className="market-list__head" aria-hidden="true">
            <span>Market</span>
            <span>Vol</span>
            <span>24h</span>
            <span>Chance</span>
          </div>
          {events.map((event) => (
            <MarketCard key={event.id} event={event} />
          ))}
        </div>
      )}

      {(hasPrev || hasMore) && events != null && events.length > 0 ? (
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
