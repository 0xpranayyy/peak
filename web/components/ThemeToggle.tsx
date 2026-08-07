"use client";

import { useCallback, useEffect, useRef, useState } from "react";

type Theme = "dark" | "light";

export const THEME_STORAGE_KEY = "peak-theme";

/**
 * Dark/light switch — the same one peakapp.site ships.
 *
 * A plain icon button was ambiguous here: a sun could mean "you are in light
 * mode" or "press for light mode", and nothing tied it to Peak. This is the
 * landing page's switch instead — a sky with a ridge echoing the app mark, and
 * an orb that rises, crests the summit and sets as you cross over. Someone who
 * arrives via "Launch app" meets a control they have already used.
 *
 * The document's `data-theme` is set by an inline script in the head before
 * first paint (see layout.tsx); this component only reflects and changes it.
 * Reading the attribute rather than storage keeps the switch in sync with
 * whatever that script decided, including the system-preference fallback.
 */
export function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>("dark");
  const [ready, setReady] = useState(false);
  const buttonRef = useRef<HTMLButtonElement>(null);
  // Whether the visitor has made an explicit choice. Until they do, the switch
  // keeps following the OS.
  const chosen = useRef(false);

  const apply = useCallback((next: Theme) => {
    document.documentElement.setAttribute("data-theme", next);
    document.documentElement.style.colorScheme = next;
    setTheme(next);
  }, []);

  useEffect(() => {
    const current = document.documentElement.getAttribute("data-theme");
    setTheme(current === "light" ? "light" : "dark");
    setReady(true);
    try {
      chosen.current = localStorage.getItem(THEME_STORAGE_KEY) != null;
    } catch {
      // Storage unavailable — treat every load as "no choice yet".
    }

    const media = window.matchMedia("(prefers-color-scheme: light)");
    const onChange = (event: MediaQueryListEvent) => {
      if (chosen.current) return;
      apply(event.matches ? "light" : "dark");
    };
    media.addEventListener("change", onChange);
    return () => media.removeEventListener("change", onChange);
  }, [apply]);

  function toggle() {
    const next: Theme = theme === "dark" ? "light" : "dark";
    chosen.current = true;
    try {
      localStorage.setItem(THEME_STORAGE_KEY, next);
    } catch {
      // Private mode: the theme still applies for this session, it just won't
      // be remembered. Not worth surfacing.
    }

    const reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches;

    if (!document.startViewTransition || reduceMotion || !buttonRef.current) {
      apply(next);
      return;
    }

    // Sweep the new theme out from the switch itself, so the change reads as
    // something you did rather than something that happened to the page.
    const box = buttonRef.current.getBoundingClientRect();
    const x = box.left + box.width / 2;
    const y = box.top + box.height / 2;
    const reach = Math.hypot(
      Math.max(x, window.innerWidth - x),
      Math.max(y, window.innerHeight - y)
    );

    const transition = document.startViewTransition(() => apply(next));
    transition.ready
      .then(() => {
        document.documentElement.animate(
          {
            clipPath: [
              `circle(0px at ${x}px ${y}px)`,
              `circle(${reach}px at ${x}px ${y}px)`,
            ],
          },
          {
            duration: 620,
            easing: "cubic-bezier(.22,1,.36,1)",
            pseudoElement: "::view-transition-new(root)",
          }
        );
      })
      .catch(() => {
        // The browser dropped the transition; the theme is already applied.
      });
  }

  const label = `Switch to ${theme === "dark" ? "light" : "dark"} theme`;

  return (
    <button
      ref={buttonRef}
      type="button"
      className="tt"
      onClick={toggle}
      aria-pressed={theme === "light"}
      aria-label={label}
      title={label}
      // Until the effect runs the rendered state is a guess; hiding it from AT
      // for that one frame avoids announcing the wrong side.
      aria-hidden={!ready}
    >
      <span className="tt__track">
        <span className="tt__star" aria-hidden="true" />
        <span className="tt__star" aria-hidden="true" />
        <span className="tt__star" aria-hidden="true" />
        <span className="tt__orb" aria-hidden="true" />
        <svg
          className="tt__ridge"
          width="64"
          height="15"
          viewBox="0 0 64 15"
          fill="none"
          aria-hidden="true"
        >
          <path
            d="M0 15h64L47 3.6 40.5 8.6 32 0l-8.5 8.6L17 3.6 0 15Z"
            fill="currentColor"
          />
        </svg>
      </span>
    </button>
  );
}
