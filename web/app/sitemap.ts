import type { MetadataRoute } from "next";
import { fetchEvents } from "@/lib/gamma";

export const runtime = "edge";
// Rendered per request. `next-on-pages` does not support ISR, so `revalidate`
// would be a no-op on Cloudflare Pages anyway — and making it explicit keeps
// `next build` from needing live market data just to produce a bundle.
export const dynamic = "force-dynamic";

const SITE = "https://peakapp.site";

/**
 * Sitemap of live markets. This is the mechanism that turns server rendering
 * into actual traffic — without it, crawlers only ever find the home page.
 *
 * Capped at the top 200 by volume: markets churn constantly, and a sitemap full
 * of URLs that resolve away within days trains crawlers to trust it less.
 */
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const events = await fetchEvents({ limit: 200, sort: "volume" }).catch(() => []);

  return [
    {
      url: SITE,
      changeFrequency: "daily",
      priority: 1,
    },
    {
      url: `${SITE}/markets`,
      changeFrequency: "hourly",
      priority: 0.9,
    },
    ...events
      .filter((event) => event.slug)
      .map((event) => ({
        url: `${SITE}/event/${event.slug}`,
        changeFrequency: "hourly" as const,
        priority: 0.8,
      })),
  ];
}
