/**
 * Redirects only. The actual Privacy Policy, Terms of Use, and Support pages
 * moved to the marketing site (Cloudflare Pages, static HTML) at
 * peakapp.site/legal — see the website/legal directory for the real,
 * counsel-approved content.
 *
 * Why: this file used to render the full pages server-side. That meant a
 * one-line copy fix required redeploying the same backend that places live
 * orders — and worse, "pushed to git" was never actually the same thing as
 * "live", because this backend deploys manually via Railway CLI, not on
 * git push. A stale legal page sat live for a full day before that was
 * caught. A static site redeploys independently of trading infrastructure
 * and shows its deploy result immediately.
 *
 * Kept as redirects, not removed outright, so anything that cached or
 * bookmarked the old api.peakapp.site/legal/* address — including whatever
 * Apple's own review process may have recorded — still resolves.
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
