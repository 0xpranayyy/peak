"use client";

import { useCallback, useEffect, useState } from "react";
import { usePeakSession } from "@/lib/session";
import {
  cancelOrder,
  fetchDepositAddress,
  fetchOpenOrders,
  fetchPortfolio,
  type OpenOrder,
  type PortfolioSnapshot,
} from "@/lib/api";
import { cents } from "@/lib/format";

export function PortfolioClient() {
  const {
    ready,
    authenticated,
    login,
    getToken,
    session,
    syncing,
    error,
    runSetup,
    refreshSession,
    eoa,
  } = usePeakSession();
  const [portfolio, setPortfolio] = useState<PortfolioSnapshot | null>(null);
  const [orders, setOrders] = useState<OpenOrder[]>([]);
  const [depositAddress, setDepositAddress] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [cancelling, setCancelling] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [actionMsg, setActionMsg] = useState<string | null>(null);

  const reload = useCallback(async () => {
    if (!authenticated) {
      setPortfolio(null);
      setOrders([]);
      setDepositAddress(null);
      return;
    }
    setLoading(true);
    setLoadError(null);
    try {
      const token = await getToken();
      if (!token) throw new Error("Sign in again.");
      const [snap, open, deposit] = await Promise.all([
        fetchPortfolio(token),
        fetchOpenOrders(token).catch(() => [] as OpenOrder[]),
        fetchDepositAddress(token).catch(() => null),
      ]);
      setPortfolio(snap);
      setOrders(open);
      setDepositAddress(
        deposit || snap.accountWallet || session?.accountWallet || null
      );
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : "Couldn’t load portfolio.");
    } finally {
      setLoading(false);
    }
  }, [authenticated, getToken, session?.accountWallet]);

  useEffect(() => {
    void reload();
  }, [reload, session?.accountWallet, session?.ready]);

  async function onCancel(orderId: string) {
    setActionMsg(null);
    setCancelling(orderId);
    try {
      const token = await getToken();
      if (!token) throw new Error("Sign in again.");
      await cancelOrder(token, orderId);
      setOrders((prev) => prev.filter((o) => o.id !== orderId));
      setActionMsg("Order cancelled.");
    } catch (err) {
      setActionMsg(err instanceof Error ? err.message : "Cancel failed.");
    } finally {
      setCancelling(null);
    }
  }

  async function copyDeposit() {
    const addr = depositAddress;
    if (!addr) return;
    try {
      await navigator.clipboard.writeText(addr);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setActionMsg("Couldn’t copy — select the address manually.");
    }
  }

  if (!ready) {
    return <p className="empty">Loading…</p>;
  }

  if (!authenticated) {
    return (
      <div className="portfolio-empty">
        <h1>Portfolio</h1>
        <p>Sign in with Privy to see cash, positions, open orders, and your deposit wallet.</p>
        <button type="button" className="btn btn--primary" onClick={login}>
          Sign in
        </button>
      </div>
    );
  }

  const displayWallet =
    depositAddress || portfolio?.accountWallet || session?.accountWallet || null;

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
        <div className="portfolio__actions">
          <button
            type="button"
            className="btn"
            disabled={loading || syncing || (authenticated && !eoa)}
            onClick={() => {
              void refreshSession().then(() => reload());
            }}
          >
            {loading || syncing || (authenticated && !eoa) ? "Refreshing…" : "Refresh"}
          </button>
          {session?.needsDeploy ? (
            <button
              type="button"
              className="btn btn--primary"
              disabled={syncing}
              onClick={() => void runSetup().catch(() => undefined)}
            >
              {syncing ? "Setting up…" : "Finish setup"}
            </button>
          ) : null}
        </div>
      </header>

      {(error || loadError || actionMsg) && (
        <p
          className={
            actionMsg && !error && !loadError
              ? "ticket__status ticket__status--ok"
              : "ticket__status ticket__status--err"
          }
        >
          {error || loadError || actionMsg}
        </p>
      )}

      <div className="portfolio__stats">
        <div className="stat">
          <span>Cash</span>
          <b>
            {loading && !portfolio
              ? "…"
              : portfolio?.cashUSD != null
                ? `$${portfolio.cashUSD.toFixed(2)}`
                : "—"}
          </b>
          {portfolio?.cashError ? <small>{portfolio.cashError}</small> : null}
        </div>
        <div className="stat">
          <span>Deposit wallet</span>
          <b className="mono" title={displayWallet ?? undefined}>
            {displayWallet
              ? `${displayWallet.slice(0, 8)}…${displayWallet.slice(-4)}`
              : "—"}
          </b>
          {displayWallet ? (
            <button type="button" className="stat__copy" onClick={() => void copyDeposit()}>
              {copied ? "Copied" : "Copy address"}
            </button>
          ) : null}
          <small>Send USDC on Polygon to this address.</small>
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
          <h2>Open orders</h2>
        </div>
        {loading && !orders.length && !portfolio ? (
          <p className="empty">Loading orders…</p>
        ) : !orders.length ? (
          <p className="empty">No open orders.</p>
        ) : (
          <div className="positions">
            {orders.map((o) => {
              const remaining = Math.max(0, o.originalSize - o.sizeMatched);
              return (
                <div key={o.id} className="position position--row">
                  <div>
                    <div className="position__title">
                      {o.side} · {cents(o.price)} · {remaining.toFixed(2)} left
                    </div>
                    <div className="position__sub">
                      {o.status ?? "open"} ·{" "}
                      <span className="mono">{o.id.slice(0, 12)}…</span>
                    </div>
                  </div>
                  <button
                    type="button"
                    className="btn"
                    disabled={cancelling === o.id}
                    onClick={() => void onCancel(o.id)}
                  >
                    {cancelling === o.id ? "Cancelling…" : "Cancel"}
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </section>

      <section className="section" style={{ paddingTop: 12 }}>
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
                href={
                  p.eventSlug
                    ? `/event/${p.eventSlug}?side=SELL&outcome=${encodeURIComponent(p.outcome)}&shares=${p.size}`
                    : "/markets"
                }
              >
                <div>
                  <div className="position__title">{p.title}</div>
                  <div className="position__sub">
                    {p.outcome} · {p.size.toFixed(2)} shares
                    {p.avgPrice != null ? ` · avg ${cents(p.avgPrice)}` : ""}
                    {" · Sell →"}
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
