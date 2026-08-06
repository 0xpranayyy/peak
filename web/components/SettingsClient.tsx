"use client";

import { usePeakSession } from "@/lib/session";

const LANDING = "https://peakapp.site";

function short(addr: string | null | undefined): string {
  if (!addr) return "—";
  if (addr.length < 12) return addr;
  return `${addr.slice(0, 10)}…${addr.slice(-6)}`;
}

export function SettingsClient() {
  const {
    ready,
    authenticated,
    privyConfigured,
    login,
    logout,
    eoa,
    session,
    geo,
    syncing,
    userId,
  } = usePeakSession();

  if (!ready) {
    return <p className="empty">Loading…</p>;
  }

  return (
    <div className="page-body">
      <div className="page-head">
        <div>
          <h1>Settings</h1>
          <p>Account, network, and legal.</p>
        </div>
      </div>

      <div className="settings-list">
        <div className="settings-row">
          <div>
            <div className="settings-row__label">Account</div>
            <div className="settings-row__hint">
              {authenticated
                ? "Signed in with Privy. Peak syncs this session to your Polymarket trading path."
                : privyConfigured
                  ? "Sign in with email, Google, Apple, or a wallet."
                  : "Privy is not configured in this build."}
            </div>
          </div>
          <div className="settings-row__value">
            {authenticated ? (
              <button type="button" className="btn" onClick={() => void logout()}>
                Sign out
              </button>
            ) : (
              <button
                type="button"
                className="btn btn--primary"
                onClick={login}
                disabled={!privyConfigured}
              >
                Sign in
              </button>
            )}
          </div>
        </div>

        <div className="settings-row">
          <div>
            <div className="settings-row__label">Signer</div>
            <div className="settings-row__hint">EOA used for Peak / Privy session</div>
          </div>
          <div className="settings-row__value mono">
            {syncing && authenticated && !eoa ? "Syncing…" : short(eoa)}
          </div>
        </div>

        <div className="settings-row">
          <div>
            <div className="settings-row__label">Trading wallet</div>
            <div className="settings-row__hint">
              Deposit / proxy wallet linked after session sync
            </div>
          </div>
          <div className="settings-row__value mono">
            {short(session?.accountWallet ?? session?.safeAddress)}
          </div>
        </div>

        <div className="settings-row">
          <div>
            <div className="settings-row__label">Network</div>
            <div className="settings-row__hint">Polymarket trades on Polygon</div>
          </div>
          <div className="settings-row__value">Polygon (137)</div>
        </div>

        <div className="settings-row">
          <div>
            <div className="settings-row__label">Trading status</div>
            <div className="settings-row__hint">
              {session?.needsDeploy
                ? "Finish setup from Positions before placing orders."
                : session?.ready
                  ? "Ready to trade when geo allows."
                  : authenticated
                    ? "Session linked."
                    : "Sign in to sync."}
            </div>
          </div>
          <div className="settings-row__value">
            {!authenticated
              ? "Signed out"
              : session?.ready
                ? "Ready"
                : session?.needsDeploy
                  ? "Needs setup"
                  : syncing
                    ? "Syncing"
                    : "Linked"}
          </div>
        </div>

        <div className="settings-row">
          <div>
            <div className="settings-row__label">Region</div>
            <div className="settings-row__hint">From Peak edge geo check</div>
          </div>
          <div className="settings-row__value">
            {geo
              ? `${geo.country ?? "Unknown"} · ${geo.status}`
              : "Checking…"}
          </div>
        </div>

        {userId ? (
          <div className="settings-row">
            <div>
              <div className="settings-row__label">Privy user</div>
              <div className="settings-row__hint">Keys local watchlist storage</div>
            </div>
            <div className="settings-row__value mono">{userId}</div>
          </div>
        ) : null}
      </div>

      <nav className="settings-links" aria-label="Legal">
        <a href={`${LANDING}/legal/privacy`} rel="noopener">
          Privacy
        </a>
        <a href={`${LANDING}/legal/terms`} rel="noopener">
          Terms
        </a>
        <a href={`${LANDING}/legal/support`} rel="noopener">
          Support
        </a>
        <a href={LANDING} rel="noopener">
          About Peak
        </a>
      </nav>
    </div>
  );
}
