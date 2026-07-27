/**
 * Privacy / Terms / Support HTML for App Store URL fields.
 * Served at /legal/* on the trading API host (same HTTPS origin after Fly/Railway).
 *
 * Content below is a substantive draft matched to what the app actually does —
 * not placeholder filler — but still requires a lawyer's sign-off before
 * submission. Two things are intentionally left as bracketed placeholders
 * rather than invented: the governing-law jurisdiction, and the arbitration
 * provider/rules/venue (pranay chose, 2026-07-27, to leave both to counsel
 * rather than guess). The operating entity is named "Peak" per pranay's
 * instruction, pending a formal registered entity. The US-exclusion and
 * OFAC/sanctions-territory language in the Terms IS filled in — pranay
 * confirmed Peak should exclude the US, consistent with Polymarket's own
 * posture and with the "US/California ... blocked" status already handled
 * in regionGate.mjs. Re-verify the sanctioned-territory list against current
 * OFAC/UK/EU designations before treating this as final; sanctions programs
 * change.
 */

const UPDATED = "2026-07-27";
const OPERATOR = "Peak"; // Replace with the formal registered entity name once one exists.
const GOVERNING_LAW = "[GOVERNING LAW / JURISDICTION — to be set with counsel]";
const ARBITRATION_PLACEHOLDER =
  "[ARBITRATION PROVIDER, RULES, AND VENUE — to be set with counsel, or removed if disputes should go through ordinary courts]";

/**
 * Countries and regions comprehensively sanctioned or embargoed by the United
 * States, United Kingdom, or European Union as of this writing. This is a
 * factual list of public government designations, not a specific provider's
 * drafted text — but sanctions programs change, so it must be re-checked
 * against current OFAC / UK / EU lists before this page is treated as final.
 */
const RESTRICTED_TERRITORIES =
  "Cuba, Iran, North Korea, Syria, the Crimea, Donetsk, and Luhansk regions of Ukraine, " +
  "and any other country or region subject to comprehensive sanctions or embargo by the " +
  "United States, United Kingdom, or European Union";

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * @param {{ title: string, heading: string, bodyHtml: string }} opts
 */
function page({ title, heading, bodyHtml }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)} · Peak</title>
  <style>
    :root { color-scheme: light dark; --fg: #1a1a1a; --muted: #5c5c5c; --bg: #f7f7f5; --card: #fff; --accent: #0b6e4f; --line: #e3e3df; }
    @media (prefers-color-scheme: dark) {
      :root { --fg: #f2f2f0; --muted: #a8a8a4; --bg: #121411; --card: #1c1f1b; --accent: #3dba8c; --line: #2a2e29; }
    }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif;
      background: var(--bg); color: var(--fg); line-height: 1.6; }
    main { max-width: 40rem; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }
    .brand { font-size: 0.85rem; letter-spacing: 0.08em; text-transform: uppercase; color: var(--accent); font-weight: 700; }
    h1 { font-size: 1.65rem; margin: 0.35rem 0 0.75rem; font-weight: 650; }
    .badge { display: inline-block; font-size: 0.75rem; font-weight: 600; color: var(--muted);
      border: 1px solid color-mix(in srgb, var(--muted) 40%, transparent); border-radius: 4px;
      padding: 0.2rem 0.45rem; margin-bottom: 1rem; }
    .card { background: var(--card); border-radius: 10px; padding: 1.5rem 1.6rem; }
    p, li { color: var(--fg); }
    .muted { color: var(--muted); font-size: 0.92rem; }
    a { color: var(--accent); }
    nav { margin-top: 2rem; font-size: 0.9rem; }
    nav a { margin-right: 1rem; }
    ul, ol { padding-left: 1.25rem; }
    li { margin: 0.3rem 0; }
    h2 { font-size: 1.08rem; margin: 1.6rem 0 0.5rem; font-weight: 650; }
    h2:first-child { margin-top: 0; }
    hr { border: none; border-top: 1px solid var(--line); margin: 1.5rem 0; }
    .toc { font-size: 0.9rem; }
    .toc ol { padding-left: 1.1rem; }
    .toc li { margin: 0.15rem 0; }
    .toc a { color: var(--fg); text-decoration: none; }
    .toc a:hover { color: var(--accent); }
    .placeholder { background: color-mix(in srgb, var(--accent) 14%, transparent);
      border-radius: 4px; padding: 0.05rem 0.35rem; }
  </style>
</head>
<body>
  <main>
    <div class="brand">Peak</div>
    <h1>${escapeHtml(heading)}</h1>
    <div class="badge">Draft for legal review — not yet counsel-approved</div>
    <div class="card">${bodyHtml}</div>
    <nav class="muted">
      <a href="/legal/privacy">Privacy</a>
      <a href="/legal/terms">Terms</a>
      <a href="/legal/support">Support</a>
    </nav>
    <p class="muted" style="margin-top:1.5rem">Last updated: ${UPDATED}</p>
  </main>
</body>
</html>`;
}

function supportContactHtml() {
  const raw = (process.env.PEAK_SUPPORT_EMAIL || "").trim();
  if (raw && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw)) {
    const email = escapeHtml(raw);
    return `<p><strong>Email:</strong> <a href="mailto:${email}">${email}</a></p>`;
  }
  return `<p><strong>Email:</strong> <span class="placeholder">Set <code>PEAK_SUPPORT_EMAIL</code> on the API host</span> —
    once set, it appears here and in the app automatically. No code change needed.</p>`;
}

export function privacyHtml() {
  return page({
    title: "Privacy Policy",
    heading: "Privacy Policy",
    bodyHtml: `
    <p>Peak ("Peak", "we", "us") is an independent iOS app for browsing and trading
      Polymarket prediction markets. <strong>Peak is not affiliated with, endorsed by,
      or operated by Polymarket, Inc.</strong> This policy explains what data moves
      through the app and who else can see it.</p>

    <p class="muted">This is a substantive working draft, not yet reviewed by a
      lawyer. It should not be relied on as your final privacy policy until counsel
      has confirmed it against the laws that apply to where your users actually are.</p>

    <div class="toc">
      <ol>
        <li><a href="#collect">What Peak collects, and why</a></li>
        <li><a href="#store">What never leaves your device</a></li>
        <li><a href="#thirdparties">Third parties Peak relies on</a></li>
        <li><a href="#custody">Peak does not hold your funds</a></li>
        <li><a href="#retention">Retention and deletion</a></li>
        <li><a href="#kids">Age</a></li>
        <li><a href="#rights">Your choices</a></li>
        <li><a href="#changes">Changes to this policy</a></li>
        <li><a href="#contact">Contact</a></li>
      </ol>
    </div>

    <hr />

    <h2 id="collect">1. What Peak collects, and why</h2>
    <p class="muted"><strong>TL;DR:</strong> only what's needed to sign you in,
      show your positions, and let you place a trade — no ads, no tracking, no
      sale of your data.</p>
    <p>Peak is built to need as little of your data as it can and still place a
      trade. Depending on how you use the app:</p>
    <ul>
      <li><strong>Wallet identifiers.</strong> When you sign in, Peak receives a
        wallet address and, if you chose email sign-in, your email — both via
        Privy, our authentication provider. Peak never sees or stores a private key.</li>
      <li><strong>Trading instructions you send.</strong> Orders you place (token,
        side, size, price) pass through Peak's backend so an order can be
        constructed and signed, then submitted from your device to Polymarket's
        exchange. Peak's backend does not execute trades on its own initiative.</li>
      <li><strong>Portfolio and activity data.</strong> To show your positions and
        history, Peak reads them from Polymarket's systems using your wallet
        address. This is requested live and is not built into a separate profile.</li>
      <li><strong>Crash and error diagnostics.</strong> In released (non-development)
        builds, Peak uses Sentry to report crashes and hangs so bugs can be fixed.
        This is configured to exclude your IP address, device identifiers, and
        screenshots — see <a href="#thirdparties">Third parties</a> below.</li>
      <li><strong>Device region signal.</strong> Peak checks a coarse region signal
        to warn you if Polymarket restricts trading where you are. This is used
        to inform you, not to profile you, and is not stored against your identity.</li>
    </ul>
    <p>Peak does not run advertising, does not sell data, and does not use
      cross-app or cross-site tracking. Peak's iOS privacy declarations to Apple
      state <strong>no tracking</strong>.</p>

    <h2 id="store">2. What never leaves your device</h2>
    <p>Some of what makes Peak feel personal to you stays local, in iOS's standard
      on-device storage, and is not sent to Peak's servers:</p>
    <ul>
      <li>Your watchlist</li>
      <li>Price alerts you've set</li>
      <li>Category / interest preferences</li>
      <li>Appearance and accent theme choice</li>
      <li>A read-only wallet address, if you added one to view a portfolio without signing in</li>
    </ul>
    <p>Deleting the app deletes this data along with it.</p>

    <h2 id="thirdparties">3. Third parties Peak relies on</h2>
    <p class="muted"><strong>TL;DR:</strong> Peak doesn't sell your data, and
      doesn't share it beyond the providers below that Peak itself runs on.</p>
    <p>Peak is a thin client over other people's infrastructure. Each of the
      following processes some of your data under its own privacy terms:</p>
    <ul>
      <li><strong>Polymarket</strong> — the exchange itself. Market data, order
        execution, and your position history all live on Polymarket's systems.
        Peak reads and writes there on your instruction.</li>
      <li><strong>Privy</strong> — authentication and embedded wallet
        infrastructure. Handles sign-in and, if you use it, secure key management.</li>
      <li><strong>Reown / WalletConnect</strong> — used if you connect your own
        external wallet instead of an embedded one.</li>
      <li><strong>Sentry</strong> — crash and error reporting, released builds
        only. Configured with <code>sendDefaultPii</code> and screenshot/view
        attachment both switched off — it does not receive your IP, device
        identifiers, positions, or balances.</li>
      <li><strong>Cloudflare</strong> — routes some network requests at the edge
        so the app can reach Polymarket reliably from more regions.</li>
      <li><strong>Railway</strong> — hosts Peak's backend server.</li>
    </ul>

    <h2 id="custody">4. Peak does not hold your funds</h2>
    <p>Peak is non-custodial. Your funds sit in your own wallet — either one you
      already control, or an embedded wallet created for you via Privy that only
      you can authorize transactions from. Peak's backend holds exchange
      credentials used to help construct and sign order requests on your
      instruction; it does not hold, control, or have independent authority to
      move your money.</p>

    <h2 id="retention">5. Retention and deletion</h2>
    <p>On-device data is deleted when you delete the app. For data Peak's backend
      touches in the course of relaying a trade, it is kept only as long as
      needed to operate the service and meet any applicable recordkeeping
      obligation, then deleted or anonymized. To ask about or request deletion of
      data associated with your account, see <a href="#contact">Contact</a>.</p>

    <h2 id="kids">6. Age</h2>
    <p>Peak is not directed at children and is not intended for anyone under 18.
      Do not use Peak if you are under the minimum age for entering into
      financial transactions where you live, whichever is higher.</p>

    <h2 id="rights">7. Your choices and rights</h2>
    <p>You can sign out, disconnect a wallet, clear on-device data from within
      Settings, or delete the app at any time.</p>

    <p><strong>If you are in the UK or European Economic Area</strong>, you have
      rights under UK and EU data protection law (GDPR), including the right
      to: request access to and a copy of your personal data; request
      correction or deletion of it; object to or restrict certain processing;
      request portability of your data; and withdraw consent at any time where
      processing is based on consent.</p>

    <p><strong>If you are a California resident</strong>, you have rights under
      the California Consumer Privacy Act (CCPA), including the right to:
      request access to and a copy of the personal information Peak's backend
      has collected about you; request its deletion; and opt out of the "sale"
      or "sharing" of personal information as those terms are defined under
      CCPA — <strong>Peak does not sell or share your personal information</strong>
      for cross-context behavioral advertising, so there is nothing to opt out
      of today, but the right stands regardless.</p>

    <p>To exercise any of these rights, contact us — see
      <a href="#contact">Contact</a> below. We may need to verify your identity
      before acting on a request. Peak will not discriminate against you for
      exercising these rights.</p>

    <h2 id="changes">8. Changes to this policy</h2>
    <p>If this policy changes materially, the "Last updated" date below will
      change and, where required, we'll tell you in the app.</p>

    <h2 id="contact">9. Contact</h2>
    ${supportContactHtml()}
  `,
  });
}

export function termsHtml() {
  return page({
    title: "Terms of Use",
    heading: "Terms of Use",
    bodyHtml: `
    <p>These Terms govern your use of the Peak iOS app and its backend services
      (together, "Peak"), operated by <strong>${escapeHtml(OPERATOR)}</strong>.
      By using Peak, you agree to these Terms. If you do not agree, do not use
      the app.</p>

    <p class="muted">This is a substantive working draft, not yet reviewed by a
      lawyer, and should not be treated as a final, binding Terms of Service
      until counsel has reviewed it — particularly the sections on governing
      law and dispute resolution, which are placeholders below.</p>

    <div class="toc">
      <ol>
        <li><a href="#what">What Peak is — and isn't</a></li>
        <li><a href="#eligibility">Eligibility and restricted territories</a></li>
        <li><a href="#risk">Risk of loss — read this</a></li>
        <li><a href="#noadvice">Not financial advice, not a fiduciary</a></li>
        <li><a href="#account">Your wallet and account</a></li>
        <li><a href="#conduct">Acceptable use</a></li>
        <li><a href="#ip">Intellectual property</a></li>
        <li><a href="#thirdpartyterms">Third-party services</a></li>
        <li><a href="#warranty">Disclaimer of warranties</a></li>
        <li><a href="#liability">Limitation of liability</a></li>
        <li><a href="#termination">Suspension and termination</a></li>
        <li><a href="#law">Governing law</a></li>
        <li><a href="#arbitration">Dispute resolution</a></li>
        <li><a href="#changes2">Changes to these Terms</a></li>
        <li><a href="#contact2">Contact</a></li>
      </ol>
    </div>

    <hr />

    <h2 id="what">1. What Peak is — and isn't</h2>
    <p>Peak is an <strong>independent, unofficial client</strong> for browsing and
      trading markets on Polymarket. Peak is not affiliated with, endorsed by, or
      operated by Polymarket, Inc., and Peak does not operate an exchange.
      Trades you place through Peak execute on Polymarket's own systems, subject
      to Polymarket's own terms, rules, and restrictions, which apply in addition
      to these Terms.</p>

    <h2 id="eligibility">2. Eligibility and restricted territories</h2>
    <p>As a condition of using Peak, you represent and agree, each time you use
      the app, that:</p>
    <ul>
      <li>You are at least <strong>18 years old</strong>.</li>
      <li>You are <strong>not located in, a resident or citizen of, or
        organized under the laws of, the United States</strong>, and you are
        not accessing Peak on behalf of a person or entity that is. Peak's
        underlying exchange, Polymarket, does not offer its prediction-market
        products to persons in the United States, and Peak cannot make that
        access lawful by routing around it.</li>
      <li>You are not located in, a resident or national of, or organized under
        the laws of, ${RESTRICTED_TERRITORIES} (together, "Restricted
        Territories"), and you are not acting on behalf of anyone who is.</li>
      <li>You are not listed on any sanctions or restricted-party list
        maintained by the United States (including OFAC's Specially Designated
        Nationals list), the United Kingdom, or the European Union, and you are
        not owned or controlled by, or acting on behalf of, anyone who is.</li>
      <li>You will not use a VPN, proxy, or any other method to obscure your
        location in order to access Peak from the United States or a Restricted
        Territory, or to circumvent any region-based restriction Peak or
        Polymarket applies. Doing so is itself a breach of these Terms.</li>
      <li>Beyond the above, you are legally permitted, under the laws that
        apply to you, to trade on prediction markets and to use
        cryptocurrency-based financial products. It is <strong>your
        responsibility</strong>, not Peak's, to know and follow those laws.</li>
    </ul>
    <p>Peak may show a regional warning or restrict functionality based on a
      network signal. That is a courtesy, not a legal determination, and not a
      guarantee that using Peak is lawful where you are — the absence of a
      warning is not confirmation that you are eligible.</p>

    <h2 id="risk">3. Risk of loss — read this</h2>
    <p>Prediction markets involve real money and real risk. Prices move, markets
      can resolve against you, and you can lose some or all of the money you
      put in. Nothing about Peak's design — including odds displays, price
      alerts, or shareable market cards — is a promise, projection, or
      suggestion of how a market will resolve. <strong>Only trade money you can
      afford to lose.</strong></p>

    <h2 id="noadvice">4. Not financial advice, not a fiduciary</h2>
    <p>Peak provides software, not advice. Nothing in the app is a
      recommendation to buy, sell, or hold any position. Peak is not a broker,
      dealer, exchange, custodial wallet provider, money services business, or
      investment adviser, and does not act as one. Peak owes you no fiduciary
      duty of any kind, and nothing in these Terms should be read to create
      one. Any decision to trade is yours alone.</p>

    <h2 id="account">5. Your wallet and account</h2>
    <ul>
      <li>Peak is non-custodial. You are solely responsible for the security of
        your device, your sign-in credentials, and any wallet — embedded or
        external — connected to Peak.</li>
      <li>If you use an embedded wallet created through Privy, losing access to
        your sign-in method may mean losing access to funds in that wallet. Peak
        cannot recover keys it never held.</li>
      <li>You are responsible for every trade submitted from your device or
        authorized wallet, whether or not you intended it, if it resulted from a
        failure to secure your own device or credentials.</li>
    </ul>

    <h2 id="conduct">6. Acceptable use</h2>
    <p>You agree not to:</p>
    <ul>
      <li>Use Peak to violate any law, including securities, gambling, or
        exchange-control law that applies to you;</li>
      <li>Attempt to bypass, disable, or circumvent any regional restriction,
        rate limit, or security control in Peak or in Polymarket's systems;</li>
      <li>Reverse-engineer, scrape at scale, or interfere with the normal
        operation of Peak's backend or Polymarket's infrastructure;</li>
      <li>Use Peak to launder money, evade sanctions, or facilitate fraud.</li>
    </ul>

    <h2 id="ip">7. Intellectual property</h2>
    <p>The Peak name, logo, and app design are the property of ${escapeHtml(OPERATOR)}.
      Market questions, prices, and related data displayed in Peak originate from
      Polymarket and remain subject to Polymarket's own rights. You may not
      reproduce Peak's branding to imply endorsement by Peak or by Polymarket.</p>

    <h2 id="thirdpartyterms">8. Third-party services</h2>
    <p>Peak depends on Polymarket, Privy, Reown/WalletConnect, and infrastructure
      providers described in the <a href="/legal/privacy">Privacy Policy</a>.
      Peak is not responsible for the availability, accuracy, or acts of these
      third parties, including outages, API changes, or account actions they
      take against you directly.</p>

    <h2 id="warranty">9. Disclaimer of warranties</h2>
    <p>Peak is provided <strong>"as is" and "as available,"</strong> without
      warranties of any kind, express or implied, to the maximum extent
      permitted by law — including, without limitation, warranties of
      merchantability, fitness for a particular purpose, and non-infringement.
      Peak does not warrant that the app will be uninterrupted, error-free, or
      that prices or data shown are accurate or current.</p>

    <h2 id="liability">10. Limitation of liability</h2>
    <p>To the maximum extent permitted by law, ${escapeHtml(OPERATOR)} will not be
      liable for any indirect, incidental, special, consequential, or punitive
      damages, or any loss of funds, profits, or data, arising from your use of
      Peak or from any trade you place — including losses caused by a bug,
      outage, or third-party failure. Some jurisdictions do not allow these
      limitations, in which case they apply only to the extent permitted.</p>

    <h2 id="termination">11. Suspension and termination</h2>
    <p>Peak may suspend or terminate your access, in whole or part, at any time —
      including for suspected violation of these Terms, legal or regulatory
      requirements, or to protect the security of the app or its users. Peak may
      also discontinue the app or backend service entirely, with or without
      notice.</p>

    <h2 id="law">12. Governing law</h2>
    <p>These Terms are governed by the laws of <span class="placeholder">${escapeHtml(GOVERNING_LAW)}</span>,
      without regard to conflict-of-laws principles — <strong>pending final
      selection with counsel.</strong> This section is a placeholder and must
      not be treated as final.</p>

    <h2 id="arbitration">13. Dispute resolution</h2>
    <p><span class="placeholder">${escapeHtml(ARBITRATION_PLACEHOLDER)}</span></p>
    <p class="muted">Left open deliberately. Binding arbitration with a
      class-action waiver is common in comparable apps and would replace
      ordinary court litigation (other than small-claims) with individual
      arbitration before a named provider — a real trade-off for users that
      needs a lawyer's judgment, not default text.</p>

    <h2 id="changes2">14. Changes to these Terms</h2>
    <p>Peak may update these Terms from time to time. If changes are material,
      the "Last updated" date below will change and, where required, we'll tell
      you in the app. Continuing to use Peak after a change takes effect means
      you accept the updated Terms.</p>

    <h2 id="contact2">15. Contact</h2>
    ${supportContactHtml()}
  `,
  });
}

export function supportHtml() {
  return page({
    title: "Support",
    heading: "Support",
    bodyHtml: `
    <p>Need help with Peak? Start here.</p>
    ${supportContactHtml()}

    <h2>Common issues</h2>
    <ul>
      <li><strong>Trading or deposits stuck.</strong> Peak talks directly to
        Polymarket's exchange. If an order or deposit looks stuck, check your
        wallet app, your network (Peak trades on Polygon), and
        <a href="https://polymarket.com" target="_blank" rel="noopener">Polymarket's</a>
        own status before assuming it's a Peak issue.</li>
      <li><strong>Can't sign in.</strong> Peak uses Privy for authentication. Try
        signing out and back in, or reconnecting your wallet. If you're on a
        network known to restrict Polymarket, sign-in may be intermittent for
        reasons outside Peak's control.</li>
      <li><strong>"Trading isn't switched on yet."</strong> This means Peak's own
        backend configuration isn't ready for your account, not that your wallet
        is broken. Try again shortly.</li>
      <li><strong>A market or order looks wrong.</strong> Prices and fills come
        from Polymarket in real time. If something looks stale, pull to refresh;
        if it persists, tell us which market and roughly when.</li>
      <li><strong>Region restrictions.</strong> Polymarket restricts trading in
        some countries. Peak reflects that restriction; it doesn't create it,
        and Peak cannot lift it on your behalf.</li>
    </ul>

    <h2>When you contact us, please include</h2>
    <ul>
      <li>What you were trying to do</li>
      <li>What happened instead (a screenshot helps)</li>
      <li>Roughly when it happened</li>
      <li><strong>Never send us your seed phrase or private key</strong> — Peak
        support will never ask you for one.</li>
    </ul>
  `,
  });
}

/**
 * Register public GET routes (must be mounted before auth middleware).
 * @param {import("express").Express} app
 */
export function mountLegalPages(app) {
  app.get("/legal/privacy", (_req, res) => {
    res.type("html").send(privacyHtml());
  });
  app.get("/legal/terms", (_req, res) => {
    res.type("html").send(termsHtml());
  });
  app.get("/legal/support", (_req, res) => {
    res.type("html").send(supportHtml());
  });
  // Convenience redirects
  app.get("/privacy", (_req, res) => res.redirect(302, "/legal/privacy"));
  app.get("/terms", (_req, res) => res.redirect(302, "/legal/terms"));
  app.get("/support", (_req, res) => res.redirect(302, "/legal/support"));
}
