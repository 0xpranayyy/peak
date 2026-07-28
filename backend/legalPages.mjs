/**
 * Redirects only. The actual Privacy Policy, Terms of Use, and Support pages
 * live on Cloudflare Pages (static HTML) — see website/legal/.
 *
 * Temporary origin: peak-website-88n.pages.dev while apex peakapp.site SSL
 * returns Cloudflare 525. After the custom domain SSL is fixed in Cloudflare,
 * set WEBSITE_ORIGIN back to https://peakapp.site (and match Info.plist).
 *
 * Why redirects (not inlined HTML): a copy fix must not require redeploying
 * the same backend that places live orders. Kept so anything that cached
 * api.peakapp.site/legal/* — including Apple review bookmarks — still resolves.
 */

const WEBSITE_ORIGIN = "https://peak-website-88n.pages.dev";

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
