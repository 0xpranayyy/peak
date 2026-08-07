"use client";

import { useState } from "react";
import { usePeakSession } from "@/lib/session";
import { SignInSheet } from "@/components/SignInSheet";

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

export function AuthButton() {
  const { ready, authenticated, eoa, syncing } = usePeakSession();
  const [sheetOpen, setSheetOpen] = useState(false);

  if (!ready) {
    return (
      <span className="auth-muted" role="status" aria-label="Loading account">
        ···
      </span>
    );
  }

  if (!authenticated) {
    return (
      <>
        <button type="button" className="cta" onClick={() => setSheetOpen(true)}>
          Sign in
        </button>
        <SignInSheet open={sheetOpen} onClose={() => setSheetOpen(false)} reason="nav" />
      </>
    );
  }

  return (
    <div className="auth-cluster">
      <a className="auth-addr mono" href="/settings" title={eoa ?? undefined}>
        {syncing ? "Syncing…" : eoa ? shortAddress(eoa) : "Account"}
      </a>
    </div>
  );
}
