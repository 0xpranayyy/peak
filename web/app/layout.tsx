import type { Metadata, Viewport } from "next";
import { DM_Sans } from "next/font/google";
import { Providers } from "./providers";
import { AppNav } from "@/components/AppNav";
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
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#0a0a0c" },
    { media: "(prefers-color-scheme: light)", color: "#f7f7f9" },
  ],
  colorScheme: "dark light",
  // Required for `env(safe-area-inset-*)` to report anything. Without it an
  // installed iPhone app draws its nav under the notch and its footer under the
  // home indicator.
  viewportFit: "cover",
};

/**
 * Applies the saved theme before first paint.
 *
 * This has to be a blocking inline script in <head>: anything that waits for
 * React to hydrate renders one frame of the wrong theme, which reads as a
 * white flash for dark-mode users. Falls back to the OS preference when
 * nothing is stored, and to dark if storage throws (private mode).
 */
const THEME_INIT = `(function(){try{var t=localStorage.getItem("peak-theme");if(t!=="light"&&t!=="dark"){t=window.matchMedia("(prefers-color-scheme: light)").matches?"light":"dark";}document.documentElement.setAttribute("data-theme",t);}catch(e){document.documentElement.setAttribute("data-theme","dark");}})();`;

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
  manifest: "/manifest.webmanifest",
  // iOS ignores the manifest's `display` and reads these instead. Without them
  // "Add to Home Screen" produces a bookmark that opens in Safari with full
  // chrome, rather than something that behaves like an app.
  appleWebApp: {
    capable: true,
    title: "Peak",
    // `default` keeps the status bar legible in both themes; `black-translucent`
    // would draw content under it and needs the theme to be known up front,
    // which it is not until the inline script runs.
    statusBarStyle: "default",
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
    <html lang="en" className={sans.variable} suppressHydrationWarning>
      <head>
        {/* Next emits only the standardised `mobile-web-app-capable`, which iOS
            honours from 17.4. Anything older still needs the legacy name to
            launch full-screen instead of as a Safari bookmark — the same
            audience the AbortSignal fallback in lib/gamma.ts exists for. */}
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT }} />
      </head>
      <body>
        <Providers>
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
