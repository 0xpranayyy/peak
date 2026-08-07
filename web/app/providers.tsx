"use client";

import { useMemo } from "react";
import { PrivyProvider, type PrivyClientConfig } from "@privy-io/react-auth";
import { polygon } from "viem/chains";
import { PeakSessionProvider } from "@/lib/session";
import { useTheme } from "@/lib/theme";

const APP_ID = process.env.NEXT_PUBLIC_PRIVY_APP_ID ?? "";
const CLIENT_ID = process.env.NEXT_PUBLIC_PRIVY_CLIENT_ID || undefined;

/** Matches `--accent` in globals.css for each theme. */
const ACCENT = { dark: "#2dd4bf", light: "#0d9488" } as const;

export function Providers({ children }: { children: React.ReactNode }) {
  // The Privy modal renders in its own tree and can't read our CSS variables,
  // so it has to be told the theme. Pinned to "dark" it was a black sheet
  // dropped onto a white page — the one screen where a mismatch is most
  // jarring, because it is the first thing a new account sees.
  const theme = useTheme();

  const config = useMemo<PrivyClientConfig>(
    () => ({
      // Polymarket / Peak trading is Polygon-only. Prompt external wallets
      // (MetaMask etc.) onto the right chain during SIWE connect.
      defaultChain: polygon,
      supportedChains: [polygon],
      loginMethods: ["email", "google", "apple", "wallet"],
      appearance: {
        theme,
        accentColor: ACCENT[theme],
        logo: "/peak-mark.png",
        walletChainType: "ethereum-only" as const,
      },
      embeddedWallets: {
        ethereum: {
          createOnLogin: "users-without-wallets" as const,
        },
      },
    }),
    [theme]
  );

  if (!APP_ID) {
    return <PeakSessionProvider>{children}</PeakSessionProvider>;
  }

  return (
    <PrivyProvider appId={APP_ID} clientId={CLIENT_ID} config={config}>
      <PeakSessionProvider>{children}</PeakSessionProvider>
    </PrivyProvider>
  );
}
