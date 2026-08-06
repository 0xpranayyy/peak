"use client";

import { PrivyProvider } from "@privy-io/react-auth";
import { polygon } from "viem/chains";
import { PeakSessionProvider } from "@/lib/session";

const APP_ID = process.env.NEXT_PUBLIC_PRIVY_APP_ID ?? "";
const CLIENT_ID = process.env.NEXT_PUBLIC_PRIVY_CLIENT_ID || undefined;

export function Providers({ children }: { children: React.ReactNode }) {
  if (!APP_ID) {
    return <PeakSessionProvider>{children}</PeakSessionProvider>;
  }

  return (
    <PrivyProvider
      appId={APP_ID}
      clientId={CLIENT_ID}
      config={{
        // Polymarket / Peak trading is Polygon-only. Prompt external wallets
        // (MetaMask etc.) onto the right chain during SIWE connect.
        defaultChain: polygon,
        supportedChains: [polygon],
        loginMethods: ["email", "google", "apple", "wallet"],
        appearance: {
          theme: "dark",
          accentColor: "#3ddcbe",
          logo: "/PeakLogo.png",
        },
        embeddedWallets: {
          ethereum: {
            createOnLogin: "users-without-wallets",
          },
        },
      }}
    >
      <PeakSessionProvider>{children}</PeakSessionProvider>
    </PrivyProvider>
  );
}
