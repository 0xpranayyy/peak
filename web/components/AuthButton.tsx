"use client";

import { usePeakSession } from "@/lib/session";

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

export function AuthButton() {
  const { ready, authenticated, eoa, login, syncing, privyConfigured } =
    usePeakSession();

  if (!ready) {
    return (
      <span className="auth-muted" role="status" aria-label="Loading account">
        ···
      </span>
    );
  }

  if (!authenticated) {
    return (
      <button
        type="button"
        className="cta"
        onClick={login}
        disabled={!privyConfigured}
        title={
          privyConfigured
            ? undefined
            : "Add NEXT_PUBLIC_PRIVY_APP_ID to enable sign-in"
        }
      >
        Sign in
      </button>
    );
  }

  return (
    <div className="auth-cluster">
      <a
        className="auth-addr mono"
        href="/settings"
        title={eoa ?? undefined}
      >
        {syncing ? "Syncing…" : eoa ? shortAddress(eoa) : "Account"}
      </a>
    </div>
  );
}

export function GeoBanner() {
  const { geo } = usePeakSession();
  if (!geo || geo.status === "allowed") return null;

  const copy =
    geo.status === "close_only"
      ? `New positions aren’t available in ${geo.country ?? "your region"}. You can still close positions you already hold.`
      : geo.status === "unknown"
        ? "Couldn’t confirm your region. New buys are paused until geo loads; browsing still works."
        : `Trading isn’t available in ${geo.country ?? "your region"}. Browse and sign-in still work; order submit needs an allowed region.`;

  return (
    <div className="geo-banner" role="status">
      <div className="shell">{copy}</div>
    </div>
  );
}
