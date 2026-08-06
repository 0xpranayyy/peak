import type { Metadata } from "next";
import { DM_Sans } from "next/font/google";
import { Providers } from "./providers";
import { AuthButton, GeoBanner } from "@/components/AuthButton";
import "./globals.css";

const SITE = "https://app.peakapp.site";
const LANDING = "https://peakapp.site";

const sans = DM_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
  variable: "--font-sans",
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: {
    default: "Peak — Prediction markets, traded clearly",
    template: "%s · Peak",
  },
  description:
    "Browse and trade Polymarket prediction markets on Peak. Clean odds, Privy sign-in, and the same Peak backend as iOS.",
  openGraph: {
    siteName: "Peak",
    type: "website",
    url: SITE,
  },
  twitter: { card: "summary_large_image" },
  robots: { index: true, follow: true },
};

function PeakMark() {
  return (
    <svg viewBox="0 0 48 41" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
      <path fill="currentColor" d="M24 0 48 41H36L24 19 12 41H0L24 0Z" />
    </svg>
  );
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={sans.variable}>
      <body>
        <Providers>
          <GeoBanner />
          <header className="masthead">
            <div className="shell masthead__row">
              <a href="/" className="wordmark" aria-label="Peak markets home">
                <PeakMark />
                PEAK
              </a>
              <nav className="masthead__nav">
                <a href="/markets">Markets</a>
                <a href="/portfolio">Portfolio</a>
                <AuthButton />
                <a className="cta cta--ghost" href={LANDING} rel="noopener">
                  About Peak
                </a>
              </nav>
            </div>
          </header>

          <main>{children}</main>

          <footer className="footer">
            <div className="shell" style={{ display: "contents" }}>
              <span>
                Peak is an independent client. Not affiliated with Polymarket, Inc.
              </span>
              <nav style={{ display: "flex", gap: 18 }}>
                <a href={`${LANDING}/legal/privacy`}>Privacy</a>
                <a href={`${LANDING}/legal/terms`}>Terms</a>
                <a href={`${LANDING}/legal/support`}>Support</a>
              </nav>
            </div>
          </footer>
        </Providers>
      </body>
    </html>
  );
}
