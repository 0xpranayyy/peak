import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      // Search pages are thin and unbounded; the market pages are the content
      // worth crawling.
      disallow: "/search",
    },
    sitemap: "https://app.peakapp.site/sitemap.xml",
  };
}
