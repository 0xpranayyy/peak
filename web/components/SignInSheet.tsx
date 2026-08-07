"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { usePeakSession, type SignInMethod } from "@/lib/session";

const LANDING = "https://peakapp.site";

type Props = {
  open: boolean;
  onClose: () => void;
  /** Why the sheet opened, so the copy can answer the actual question. */
  reason?: "nav" | "trade" | "positions";
};

const HEADING: Record<NonNullable<Props["reason"]>, string> = {
  nav: "Sign in to Peak",
  trade: "Sign in to place this order",
  positions: "Sign in to see your positions",
};

/**
 * The step before Privy's modal.
 *
 * Privy on its own asks "email or wallet?" without ever saying what the account
 * is for or who ends up holding the money — the two things someone about to
 * connect a wallet actually wants to know. This answers both, and each method
 * here opens Privy already on that method, so it costs a click of information,
 * not a click of navigation.
 */
export function SignInSheet({ open, onClose, reason = "nav" }: Props) {
  const { login, privyConfigured } = usePeakSession();
  const panelRef = useRef<HTMLDivElement>(null);
  const restoreFocus = useRef<HTMLElement | null>(null);
  // Portalled to <body>, and not optionally: the masthead sets `backdrop-filter`,
  // which makes it a containing block for `position: fixed`. Rendered in place,
  // the scrim's `inset: 0` resolved to the 60px-tall header and the dialog was
  // centred inside — and clipped by — the nav bar.
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const start = useCallback(
    (method: SignInMethod) => {
      onClose();
      login({ loginMethods: [method] });
    },
    [login, onClose]
  );

  useEffect(() => {
    if (!open) return;

    restoreFocus.current = document.activeElement as HTMLElement | null;
    // Focus the dialog itself, not its first button — that is the close control,
    // and opening a sign-in sheet with "dismiss" pre-selected reads as the app
    // suggesting you leave.
    panelRef.current?.focus();

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        onClose();
      }
    };
    document.addEventListener("keydown", onKeyDown);

    // The page behind a modal must not scroll under it.
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previousOverflow;
      restoreFocus.current?.focus?.();
    };
  }, [open, onClose]);

  if (!open || !mounted) return null;

  return createPortal(
    <div
      className="sheet-scrim"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        className="sheet"
        role="dialog"
        aria-modal="true"
        aria-labelledby="signin-title"
        ref={panelRef}
        tabIndex={-1}
      >
        <button
          type="button"
          className="sheet__close"
          onClick={onClose}
          aria-label="Close"
        >
          <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
            <path
              d="M6 6l12 12M18 6L6 18"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
            />
          </svg>
        </button>

        <div className="sheet__head">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/peak-mark.png" width={44} height={44} alt="" className="sheet__mark" />
          <h2 id="signin-title">{HEADING[reason]}</h2>
          <p>
            Browsing markets is open to everyone. An account is only needed to
            place and hold orders.
          </p>
        </div>

        {privyConfigured ? (
          <div className="sheet__methods">
            <button type="button" className="method" onClick={() => start("email")}>
              <MailIcon />
              <span>Continue with email</span>
            </button>
            <button type="button" className="method" onClick={() => start("google")}>
              <GoogleIcon />
              <span>Continue with Google</span>
            </button>
            <button type="button" className="method" onClick={() => start("apple")}>
              <AppleIcon />
              <span>Continue with Apple</span>
            </button>
            <button
              type="button"
              className="method method--alt"
              onClick={() => start("wallet")}
            >
              <WalletIcon />
              <span>Connect an existing wallet</span>
            </button>
          </div>
        ) : (
          <p className="sheet__unavailable">
            Sign-in isn’t configured on this deployment. Set
            <code> NEXT_PUBLIC_PRIVY_APP_ID</code> to enable it.
          </p>
        )}

        <ul className="sheet__facts">
          <li>
            <b>You hold the keys.</b> Email and social sign-in create a wallet
            only you control. Peak never takes custody of your funds.
          </li>
          <li>
            <b>Orders settle on Polymarket.</b> Peak is an independent client —
            trades rest on Polymarket’s order book, on Polygon.
          </li>
        </ul>

        <p className="sheet__legal">
          By continuing you agree to the{" "}
          <a href={`${LANDING}/legal/terms`} target="_blank" rel="noreferrer">
            Terms
          </a>{" "}
          and{" "}
          <a href={`${LANDING}/legal/privacy`} target="_blank" rel="noreferrer">
            Privacy Policy
          </a>
          .
        </p>
      </div>
    </div>,
    document.body
  );
}

function MailIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none">
      <rect
        x="2.75"
        y="5"
        width="18.5"
        height="14"
        rx="2.5"
        stroke="currentColor"
        strokeWidth="1.7"
      />
      <path
        d="M3.5 7.5l7.4 5.2a2 2 0 0 0 2.2 0l7.4-5.2"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
      />
    </svg>
  );
}

function GoogleIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
      <path
        fill="#4285F4"
        d="M21.6 12.23c0-.7-.06-1.37-.18-2.02H12v3.82h5.38a4.6 4.6 0 0 1-2 3.02v2.51h3.24c1.89-1.74 2.98-4.3 2.98-7.33Z"
      />
      <path
        fill="#34A853"
        d="M12 22c2.7 0 4.96-.9 6.62-2.44l-3.24-2.51c-.9.6-2.04.96-3.38.96-2.6 0-4.8-1.76-5.59-4.12H3.06v2.6A10 10 0 0 0 12 22Z"
      />
      <path
        fill="#FBBC05"
        d="M6.41 13.89a6 6 0 0 1 0-3.78v-2.6H3.06a10 10 0 0 0 0 8.98l3.35-2.6Z"
      />
      <path
        fill="#EA4335"
        d="M12 5.98c1.47 0 2.79.5 3.83 1.5l2.87-2.87C16.95 2.99 14.7 2 12 2a10 10 0 0 0-8.94 5.51l3.35 2.6C7.2 7.75 9.4 5.98 12 5.98Z"
      />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="currentColor">
      <path d="M16.8 12.7c0-2 1.64-2.98 1.71-3.02-.94-1.37-2.39-1.56-2.9-1.58-1.23-.13-2.4.72-3.02.72-.63 0-1.59-.7-2.62-.68-1.34.02-2.58.78-3.27 1.99-1.41 2.43-.36 6.03 1 8 .67.96 1.45 2.03 2.49 1.99 1-.04 1.39-.64 2.61-.64 1.22 0 1.57.64 2.63.62 1.09-.02 1.77-.97 2.43-1.94.78-1.12 1.09-2.21 1.11-2.26-.02-.01-2.16-.83-2.16-3.2Z" />
      <path d="M14.7 6.73c.55-.67.92-1.61.82-2.53-.79.03-1.75.53-2.32 1.2-.51.59-.96 1.54-.84 2.45.88.07 1.77-.45 2.34-1.12Z" />
    </svg>
  );
}

function WalletIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none">
      <rect
        x="2.75"
        y="5.75"
        width="18.5"
        height="12.5"
        rx="2.5"
        stroke="currentColor"
        strokeWidth="1.7"
      />
      <path
        d="M16 12h2.5"
        stroke="currentColor"
        strokeWidth="2.2"
        strokeLinecap="round"
      />
    </svg>
  );
}
