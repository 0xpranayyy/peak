"use client";

import { useEffect, useState } from "react";

export type Theme = "dark" | "light";

export const THEME_STORAGE_KEY = "peak-theme";

/**
 * The live value of `<html data-theme>`.
 *
 * The attribute is the single source of truth: an inline script in the document
 * head sets it before first paint, and ThemeToggle rewrites it. Anything that
 * needs the theme in JavaScript — third-party widgets that can't read our CSS
 * variables, chiefly the Privy modal — should observe it here rather than
 * re-reading localStorage, which would miss the system-preference fallback and
 * go stale the moment someone flips the switch.
 *
 * Starts at "dark" so server and first client render agree; the effect
 * corrects it before paint-relevant work.
 */
export function useTheme(): Theme {
  const [theme, setTheme] = useState<Theme>("dark");

  useEffect(() => {
    const root = document.documentElement;
    const read = () =>
      setTheme(root.getAttribute("data-theme") === "light" ? "light" : "dark");

    read();
    const observer = new MutationObserver(read);
    observer.observe(root, { attributes: true, attributeFilter: ["data-theme"] });
    return () => observer.disconnect();
  }, []);

  return theme;
}
