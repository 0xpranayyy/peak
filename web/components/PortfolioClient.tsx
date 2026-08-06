"use client";

import { useEffect, useState } from "react";
import { usePeakSession } from "@/lib/session";
import { fetchPortfolio, type PortfolioSnapshot } from "@/lib/api";
import { cents } from "@/lib/format";

export function PortfolioClient() {
  const { ready, authenticated, login, getToken, session, syncing, error, runSetup, eoa } =
    usePeakSession();
  const [portfolio, setPortfolio] = useState<PortfolioSnapshot | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!authenticated) {
      setPortfolio(null);
      return;
    }
    let cancelled = false;
    (async () => {
      setLoading(true);
      setLoadError(null);
      try {
        const token = await getToken();
        if (!token) throw new Error("Sign in again.");
        const snap = await fetchPortfolio(token);
        if (!cancelled) setPortfolio(snap);
      } catch (err) {
        if (!cancelled) {
          setLoadError(err instanceof Error ? err.message : "Couldn’t load portfolio.");
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [authenticated, getToken, session?.accountWallet, session?.ready]);

  if (!ready) {
    return <p className="empty">Loading…</p>;
  }

  if (!authenticated) {
    return (
      <div className="portfolio-empty">
        <h1>Portfolio</h1>
        <p>Sign in with Privy to see cash, positions, and your deposit wallet.</p>
        <button type="button" className="btn btn--primary" onClick={login}>
          Sign in
        </button>
      </div>
    );
  }

  return (
    <div className="portfolio">
      <header className="portfolio__head">
        <div>
          <h1>Portfolio</h1>
          <p className="lede" style={{ marginTop: 8 }}>
            {eoa ? (
              <>
                Signer <span className="mono">{eoa}</span>
              </>
            ) : (
              "Syncing wallet…"
            )}
          </p>
        </div>
        {session?.needsDeploy ? (
          <button
            type="button"
            className="btn"
            disabled={syncing}
            onClick={() => void runSetup().catch(() => undefined)}
          >
            {syncing ? "Setting up…" : "Finish setup"}
          </button>
        ) : null}
      </header>

      {(error || loadError) && (
        <p className="ticket__status ticket__status--err">{error || loadError}</p>
      )}

      <div className="portfolio__stats">
        <div className="stat">
          <span>Cash</span>
          <b>
            {loading
              ? "…"
              : portfolio?.cashUSD != null
                ? `$${portfolio.cashUSD.toFixed(2)}`
                : "—"}
          </b>
          {portfolio?.cashError ? (
            <small>{portfolio.cashError}</small>
          ) : null}
        </div>
        <div className="stat">
          <span>Deposit wallet</span>
          <b className="mono">
            {portfolio?.accountWallet
              ? `${portfolio.accountWallet.slice(0, 8)}…${portfolio.accountWallet.slice(-4)}`
              : session?.accountWallet
                ? `${session.accountWallet.slice(0, 8)}…`
                : "—"}
          </b>
        </div>
        <div className="stat">
          <span>Status</span>
          <b>
            {session?.ready
              ? "Ready"
              : session?.needsDeploy
                ? "Needs setup"
                : syncing
                  ? "Syncing"
                  : "Linked"}
          </b>
        </div>
      </div>

      {portfolio?.needsImport ? (
        <p className="notice">
          <b>Existing Polymarket wallets</b> that need a key import can only be
          linked in the Peak iOS app. Web sign-in is Privy-only — Peak never asks
          for a seed phrase in the browser.
        </p>
      ) : null}

      <section className="section" style={{ paddingTop: 28 }}>
        <div className="section__head">
          <h2>Positions</h2>
        </div>
        {loading && !portfolio ? (
          <p className="empty">Loading positions…</p>
        ) : !portfolio?.positions.length ? (
          <p className="empty">No open positions yet. Browse markets to trade.</p>
        ) : (
          <div className="positions">
            {portfolio.positions.map((p, i) => (
              <a
                key={`${p.title}-${p.outcome}-${i}`}
                className="position"
                href={p.eventSlug ? `/event/${p.eventSlug}` : "/markets"}
              >
                <div>
                  <div className="position__title">{p.title}</div>
                  <div className="position__sub">
                    {p.outcome} · {p.size.toFixed(2)} shares
                    {p.avgPrice != null ? ` · avg ${cents(p.avgPrice)}` : ""}
                  </div>
                </div>
                <div className="position__right">
                  {p.curPrice != null ? <b>{cents(p.curPrice)}</b> : null}
                  {p.cashPnl != null ? (
                    <span className={p.cashPnl >= 0 ? "pnl pnl--up" : "pnl pnl--down"}>
                      {p.cashPnl >= 0 ? "+" : "-"}${Math.abs(p.cashPnl).toFixed(2)}
                    </span>
                  ) : null}
                </div>
              </a>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
