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
