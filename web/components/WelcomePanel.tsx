"use client";

import { useEffect, useState } from "react";

const STORAGE_KEY = "peak.web.welcome.v1";
const LANDING = "https://peakapp.site";

/**
 * First-run orientation on the markets feed.
 *
 * Someone arriving from "Launch app" on peakapp.site has read a pitch and then
 * lands on a table of numbers. This bridges the two: what the columns mean, that
 * looking around costs nothing, and where the money actually sits. It renders
 * inline rather than as a modal — a dialog in front of the content you just
 * asked to see is a toll, not a welcome.
 *
 * Starts hidden and is revealed by the effect, so a returning visitor never sees
 * it flash before the storage check runs.
 */
export function WelcomePanel() {
  const [visible, setVisible] = useState(false);
  const [leaving, setLeaving] = useState(false);

  useEffect(() => {
    try {
      if (localStorage.getItem(STORAGE_KEY) !== "dismissed") setVisible(true);
    } catch {
      // Storage blocked: show it. Being greeted twice beats never being told
      // what the page is.
      setVisible(true);
    }
  }, []);

  function dismiss() {
    setLeaving(true);
    try {
      localStorage.setItem(STORAGE_KEY, "dismissed");
    } catch {
      // Nothing to do — it will greet them again next time.
    }
    window.setTimeout(() => setVisible(false), 200);
  }

  if (!visible) return null;

  return (
    <section className={leaving ? "welcome welcome--leaving" : "welcome"}>
      <button
        type="button"
        className="welcome__close"
        onClick={dismiss}
        aria-label="Dismiss welcome"
      >
        <svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true">
          <path
            d="M6 6l12 12M18 6L6 18"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
          />
        </svg>
      </button>

      <div className="welcome__intro">
        <p className="welcome__eyebrow">The Peak exchange</p>
        <h2>Odds move. You act.</h2>
        <p className="welcome__lede">
          Live prediction markets from Polymarket, in a client built for reading
          fast and trading without ceremony.
        </p>
      </div>

      <ul className="welcome__points">
        <li>
          <span className="welcome__num">1</span>
          <div>
            <b>Read the odds</b>
            <p>
              The big number is the market’s price on the leading outcome. 62%
              means traders are paying 62¢ for a $1 payout — a probability, not a
              forecast.
            </p>
          </div>
        </li>
        <li>
          <span className="welcome__num">2</span>
          <div>
            <b>Open a row to trade</b>
            <p>
              Each market opens a terminal: price history, the live order book,
              and a ticket. Browsing needs no account.
            </p>
          </div>
        </li>
        <li>
          <span className="welcome__num">3</span>
          <div>
            <b>Your funds stay yours</b>
            <p>
              Sign in when you want to place an order. Peak never takes custody —
              orders rest on Polymarket’s book, on Polygon.
            </p>
          </div>
        </li>
      </ul>

      <div className="welcome__actions">
        <button type="button" className="btn btn--primary" onClick={dismiss}>
          Start browsing
        </button>
        <a className="btn btn--ghost" href={LANDING} rel="noopener">
          About Peak
        </a>
      </div>
    </section>
  );
}
