"use client";

import { useCallback, useEffect, useState, useSyncExternalStore } from "react";
import { usePeakSession } from "@/lib/session";
import {
  listWatchlist,
  removeFromWatchlist,
  toggleWatchlist,
} from "@/lib/watchlist";

const listeners = new Set<() => void>();

function emit(): void {
  listeners.forEach((l) => l());
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

let version = 0;
function getSnapshot(): number {
  return version;
}
function getServerSnapshot(): number {
  return 0;
}

function bump(): void {
  version += 1;
  emit();
}

export function useWatchlist() {
  const { userId } = usePeakSession();
  const userKey = userId || "anon";
  const ver = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const [ids, setIds] = useState<string[]>([]);

  useEffect(() => {
    setIds(listWatchlist(userKey));
  }, [userKey, ver]);

  const contains = useCallback(
    (eventId: string) => ids.includes(eventId),
    [ids]
  );

  const toggle = useCallback(
    (eventId: string) => {
      const next = toggleWatchlist(userKey, eventId);
      bump();
      setIds(next);
      return next;
    },
    [userKey]
  );

  const remove = useCallback(
    (eventId: string) => {
      const next = removeFromWatchlist(userKey, eventId);
      bump();
      setIds(next);
      return next;
    },
    [userKey]
  );

  return { userKey, ids, contains, toggle, remove };
}
