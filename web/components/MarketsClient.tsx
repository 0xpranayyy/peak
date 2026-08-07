"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  DEFAULT_SORT,
  fetchEventPage,
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
};

/**
 * Markets feed loads in the browser on purpose.
 *
 * Gamma `/events?limit=24` is multi-MB once nested markets are included.
 * Cloudflare Pages Functions routinely CPU-trip while `JSON.parse`-ing that
 * during SSR, which emptied the feed and cascaded into event-page failures.
 * The edge Worker already allows browser CORS (`*`), so the same client that
 * reads CLOB can read the feed without burning the SSR isolate.
 *
 * Paging appends rather than replaces. Numbered pages meant every step threw
 * away rows already on screen, reset the scroll position and re-fetched from
 * zero; you could not get back to where you were without paying for the whole
 * page again. Nothing is fetched until asked for — no scroll-triggered
 * prefetch, because a feed that keeps loading while you read is how you end up
 * pulling megabytes nobody looked at.
 */
export function MarketsClient({ tag, sort }: Props) {
  const match = categoryFromSlug(tag);
  const activeTag = match?.slug;
  const activeSort: SortKey = SORTS.includes(sort as SortKey)
    ? (sort as SortKey)
    : DEFAULT_SORT;

  const [events, setEvents] = useState<PeakEvent[] | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [total, setTotal] = useState<number | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<"initial" | "more" | null>(null);

  // Held across renders so "load more" can cancel in flight when the filters
  // change underneath it.
  const abortRef = useRef<AbortController | null>(null);
  /**
   * Where the next window starts. Counted in rows Gamma returned, not rows that
   * survived `isListEligible` — offsetting by the filtered count would re-ask
   * for the finished games we just dropped and stall the feed on them.
   */
  const nextOffset = useRef(0);

  useEffect(() => {
    const controller = new AbortController();
    abortRef.current?.abort();
    abortRef.current = controller;

    setEvents(null);
    setHasMore(false);
    setTotal(null);
    setError(null);
    nextOffset.current = 0;

    (async () => {
      try {
        const page = await fetchEventPage({
          limit: PAGE_SIZE,
          offset: 0,
          sort: activeSort,
          tagSlug: activeTag,
          signal: controller.signal,
        });
        if (controller.signal.aborted) return;
        nextOffset.current = PAGE_SIZE;
        setEvents(page.events);
        setHasMore(page.hasMore);
        setTotal(page.total);
      } catch {
        if (controller.signal.aborted) return;
        setEvents([]);
        setError("initial");
      }
    })();

    return () => controller.abort();
  }, [activeTag, activeSort]);

  const loadMore = useCallback(async () => {
    if (loadingMore || events == null) return;
    const controller = new AbortController();
    abortRef.current?.abort();
    abortRef.current = controller;

    setLoadingMore(true);
    setError(null);
    try {
      const page = await fetchEventPage({
        limit: PAGE_SIZE,
        offset: nextOffset.current,
        sort: activeSort,
        tagSlug: activeTag,
        signal: controller.signal,
      });
      if (controller.signal.aborted) return;
      nextOffset.current += PAGE_SIZE;
      setEvents((prev) => {
        const base = prev ?? [];
        // Gamma can repeat a row across windows when volume shifts mid-scroll.
        const seen = new Set(base.map((e) => e.id));
        return [...base, ...page.events.filter((e) => !seen.has(e.id))];
      });
      setHasMore(page.hasMore);
      if (page.total != null) setTotal(page.total);
    } catch {
      if (controller.signal.aborted) return;
      setError("more");
    } finally {
      if (!controller.signal.aborted) setLoadingMore(false);
    }
  }, [activeSort, activeTag, events, loadingMore]);

  const shown = events?.length ?? 0;
  const countLabel =
    events == null || shown === 0
      ? null
      : total != null
        ? `${shown} of ${total.toLocaleString()}`
        : `${shown}${hasMore ? "+" : ""} markets`;

  return (
    <div className="shell page-body">
      <WelcomePanel />

      <div className="page-head page-head--markets">
        <div>
          <h1>{match ? match.child?.label ?? match.parent.label : "Markets"}</h1>
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
        <Filters match={match} activeSort={activeSort} />
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
            {error === "initial"
              ? "Markets unavailable"
              : match
                ? `No open markets in ${match.child?.label ?? match.parent.label}`
                : "Markets unavailable"}
          </p>
          <p className="empty-state__body">
            {error === "initial"
              ? "The feed didn’t load. Try again in a moment."
              : match
                ? "This section is quiet right now — seasonal ones fill up again when play resumes. Try another."
                : "The feed didn’t load. Try again in a moment."}
          </p>
          {match ? (
            <a className="btn" href="/markets">
              Reset filters
            </a>
          ) : null}
        </div>
      ) : (
        <>
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

          {hasMore ? (
            <div className="feed-more">
              <button
                type="button"
                className="btn"
                onClick={() => void loadMore()}
                disabled={loadingMore}
              >
                {loadingMore ? "Loading…" : "Load more markets"}
              </button>
              {error === "more" ? (
                <p className="feed-more__error" role="alert">
                  That didn’t load. Try again.
                </p>
              ) : null}
            </div>
          ) : (
            <p className="feed-more feed-more__end">
              That’s every open market here.
            </p>
          )}
        </>
      )}
    </div>
  );
}
