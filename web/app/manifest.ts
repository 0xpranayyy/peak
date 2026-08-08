import type { MetadataRoute } from "next";

/**
 * Web app manifest — what makes Peak installable to a phone home screen.
 *
 * Served by Next at `/manifest.webmanifest`. `display: standalone` is the part
 * that matters: launched from the home screen the browser chrome disappears, so
 * the URL bar and tab strip stop eating vertical space on a trading screen.
 *
 * `start_url` is `/markets` rather than `/`, which only redirects. An installed
 * app should not spend its first paint on a 307.
 */
export const dynamic = "force-static";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Peak — Prediction markets",
    short_name: "Peak",
    description:
      "Trade Polymarket prediction markets on Peak. Live odds, real order books, self-custodial.",
    start_url: "/markets",
    scope: "/",
    display: "standalone",
    orientation: "portrait",
    // Matches `--ink` in the dark theme, which is what the app opens in unless
    // the device says otherwise. The `theme-color` meta tags in layout.tsx
    // carry the per-scheme values; this is the install-time splash colour.
    background_color: "#0a0a0c",
    theme_color: "#0a0a0c",
    categories: ["finance", "news"],
    icons: [
      { src: "/favicon-32.png", sizes: "32x32", type: "image/png" },
      { src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      // `maskable` lets Android crop to its own icon shape instead of
      // letterboxing the square into a circle.
      { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
    shortcuts: [
      { name: "Markets", url: "/markets" },
      { name: "Positions", url: "/positions" },
      { name: "Watchlist", url: "/watchlist" },
    ],
  };
}
