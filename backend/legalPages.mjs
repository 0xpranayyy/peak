/**
 * Redirects only. The actual Privacy Policy, Terms of Use, and Support pages
 * live on Cloudflare Pages (static HTML) — see website/legal/.
 *
 * Origin is the apex domain. (The earlier peak-website-88n.pages.dev workaround
 * for a Cloudflare 525 on peakapp.site is no longer needed — the apex serves
 * both the legal pages and the AASA file correctly.)
 *
 * Why redirects (not inlined HTML): a copy fix must not require redeploying
 * the same backend that places live orders. Kept so anything that cached
 * api.peakapp.site/legal/* — including Apple review bookmarks — still resolves.
 */

const WEBSITE_ORIGIN = "https://peakapp.site";

/**
 * @param {import("express").Express} app
 */
export function mountLegalPages(app) {
  app.get("/legal/privacy", (_req, res) => res.redirect(301, `${WEBSITE_ORIGIN}/legal/privacy`));
  app.get("/legal/terms", (_req, res) => res.redirect(301, `${WEBSITE_ORIGIN}/legal/terms`));
  app.get("/legal/support", (_req, res) => res.redirect(301, `${WEBSITE_ORIGIN}/legal/support`));
  // Convenience aliases some earlier drafts also used.
  app.get("/privacy", (_req, res) => res.redirect(301, `${WEBSITE_ORIGIN}/legal/privacy`));
  app.get("/terms", (_req, res) => res.redirect(301, `${WEBSITE_ORIGIN}/legal/terms`));
  app.get("/support", (_req, res) => res.redirect(301, `${WEBSITE_ORIGIN}/legal/support`));
}
