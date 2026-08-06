import type { Metadata, Viewport } from "next";
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

export const viewport: Viewport = {
  themeColor: "#09090b",
  colorScheme: "dark",
};

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: {
    default: "Peak — Markets",
    template: "%s · Peak",
  },
  description:
    "Trade Polymarket prediction markets on Peak. Live odds, Privy sign-in, real positions.",
  applicationName: "Peak",
  icons: {
    icon: [
      { url: "/favicon-16.png", sizes: "16x16", type: "image/png" },
      { url: "/favicon-32.png", sizes: "32x32", type: "image/png" },
      { url: "/peak-mark.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
  },
  openGraph: {
    siteName: "Peak",
    type: "website",
    url: SITE,
    title: "Peak — Markets",
    description:
      "Trade Polymarket prediction markets on Peak. Live odds, Privy sign-in, real positions.",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Peak",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Peak — Markets",
    description:
      "Trade Polymarket prediction markets on Peak. Live odds, Privy sign-in, real positions.",
    images: ["/og.png"],
  },
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
            <div className="shell footer__inner">
              <span className="footer__brand">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src="/peak-mark.png"
                  width={16}
                  height={16}
                  alt=""
                  className="footer__mark"
                  decoding="async"
                />
                Peak is an independent client. Not affiliated with Polymarket, Inc.
              </span>
              <nav className="footer__nav" aria-label="Legal">
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
