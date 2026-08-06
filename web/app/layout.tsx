import type { Metadata } from "next";
import { DM_Sans } from "next/font/google";
import { Providers } from "./providers";
import { AppNav } from "@/components/AppNav";
import { GeoBanner } from "@/components/AuthButton";
import "./globals.css";

const SITE = "https://app.peakapp.site";
const LANDING = "https://peakapp.site";

const sans = DM_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-sans",
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: {
    default: "Peak — Markets",
    template: "%s · Peak",
  },
  description:
    "Trade Polymarket prediction markets on Peak. Live odds, Privy sign-in, real positions.",
  openGraph: {
    siteName: "Peak",
    type: "website",
    url: SITE,
  },
  twitter: { card: "summary_large_image" },
  robots: { index: true, follow: true },
};

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
            <div className="shell">
              <AppNav />
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
