/**
 * Local watchlist of Polymarket event IDs.
 *
 * Keyed by Privy user id when signed in, otherwise `anon`. Only real event
 * IDs are stored — no default fake markets.
 */

const PREFIX = "peak.watchlist.v1";

function storageKey(userKey: string): string {
  return `${PREFIX}:${userKey}`;
}

function readIds(userKey: string): string[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(storageKey(userKey));
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .map((id) => (typeof id === "string" ? id.trim() : ""))
      .filter((id) => id.length > 0);
  } catch {
    return [];
  }
}

function writeIds(userKey: string, ids: string[]): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(storageKey(userKey), JSON.stringify(ids));
}

export function listWatchlist(userKey: string): string[] {
  return readIds(userKey || "anon");
}

export function isWatched(userKey: string, eventId: string): boolean {
  return listWatchlist(userKey).includes(eventId);
}

export function toggleWatchlist(userKey: string, eventId: string): string[] {
  const key = userKey || "anon";
  const id = eventId.trim();
  if (!id) return listWatchlist(key);
  const current = listWatchlist(key);
  const next = current.includes(id)
    ? current.filter((x) => x !== id)
    : [id, ...current.filter((x) => x !== id)];
  writeIds(key, next);
  return next;
}

export function removeFromWatchlist(userKey: string, eventId: string): string[] {
  const key = userKey || "anon";
  const next = listWatchlist(key).filter((x) => x !== eventId);
  writeIds(key, next);
  return next;
}
