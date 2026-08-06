"use client";

import { useWatchlist } from "@/lib/watchlist-hook";

export function WatchlistToggle({
  eventId,
  compact = false,
}: {
  eventId: string;
  compact?: boolean;
}) {
  const { contains, toggle } = useWatchlist();
  const on = contains(eventId);

  return (
    <button
      type="button"
      className={on ? "btn" : "btn btn--ghost"}
      aria-pressed={on}
      onClick={() => toggle(eventId)}
      title={on ? "Remove from watchlist" : "Add to watchlist"}
    >
      {compact ? (on ? "Watching" : "Watch") : on ? "Watching" : "Watch"}
    </button>
  );
}
