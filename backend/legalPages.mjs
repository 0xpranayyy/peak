/**
 * Draft Privacy / Terms / Support HTML for App Store URL fields.
 * Served at /legal/* on the trading API host (same HTTPS origin after Fly/Railway).
 * Placeholder language only — not counsel-reviewed; replace before App Store submission.
 */

const UPDATED = "2026-07-25";

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
    :root { color-scheme: light dark; --fg: #1a1a1a; --muted: #5c5c5c; --bg: #f7f7f5; --card: #fff; --accent: #0b6e4f; }
    @media (prefers-color-scheme: dark) {
      :root { --fg: #f2f2f0; --muted: #a8a8a4; --bg: #121411; --card: #1c1f1b; --accent: #3dba8c; }
    }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif;
      background: var(--bg); color: var(--fg); line-height: 1.55; }
    main { max-width: 40rem; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }
    .brand { font-size: 0.85rem; letter-spacing: 0.08em; text-transform: uppercase; color: var(--accent); font-weight: 700; }
    h1 { font-size: 1.65rem; margin: 0.35rem 0 0.75rem; font-weight: 650; }
    .badge { display: inline-block; font-size: 0.75rem; font-weight: 600; color: var(--muted);
      border: 1px solid color-mix(in srgb, var(--muted) 40%, transparent); border-radius: 4px;
      padding: 0.2rem 0.45rem; margin-bottom: 1rem; }
    .card { background: var(--card); border-radius: 10px; padding: 1.25rem 1.35rem; }
    p, li { color: var(--fg); }
    .muted { color: var(--muted); font-size: 0.92rem; }
    a { color: var(--accent); }
    nav { margin-top: 2rem; font-size: 0.9rem; }
    nav a { margin-right: 1rem; }
    ul { padding-left: 1.2rem; }
    h2 { font-size: 1.05rem; margin: 1.35rem 0 0.4rem; font-weight: 650; }
  </style>
</head>
<body>
  <main>
    <div class="brand">Peak</div>
    <h1>${escapeHtml(heading)}</h1>
    <div class="badge">Draft — not legal counsel–final · update before App Store</div>
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
    return `<p><strong>Contact:</strong> <a href="mailto:${email}">${email}</a></p>`;
  }
  return `<p><strong>Contact:</strong> Contact support from the Peak app settings / email TBD.
    Optionally set <code>PEAK_SUPPORT_EMAIL</code> on the API host (e.g. <code>support@</code> your domain) to show a mailto link here.</p>`;
}

export function privacyHtml() {
  return page({
    title: "Privacy Policy",
    heading: "Privacy Policy",
    bodyHtml: `
    <p><strong>Draft only.</strong> This page is a plain-language placeholder for App Store URL fields.
      It is <em>not</em> a counsel-approved privacy policy and is not legal advice. Peak will replace it with
      reviewed copy before App Store submission.</p>

    <h2>Who we are</h2>
    <p>Peak is an <strong>unofficial Polymarket client</strong> (iOS app and optional trading API).
      It is not affiliated with, endorsed by, or operated by Polymarket, Inc.</p>

    <h2>What Peak may process</h2>
    <p>Depending on how you use the app, Peak or its service providers may process:</p>
    <ul>
      <li><strong>Sign-in data</strong> — identifiers from Privy (for example email or wallet address) when you create or use an account</li>
      <li><strong>Trading activity you start</strong> — order and portfolio requests sent through Peak’s backend to Polymarket’s systems</li>
      <li><strong>Device / diagnostics</strong> — crash or usage data you share through Apple (e.g. App Store / crash reports), if enabled</li>
      <li><strong>On-device preferences</strong> — settings such as watchlists, alerts, or category choices stored on your device</li>
    </ul>

    <h2>Third parties</h2>
    <p>Market data may come from Polymarket’s public APIs. Authentication and wallet features may involve
      Privy and/or your own wallet app (for example WalletConnect). Those providers have their own privacy policies.</p>

    <h2>Your choices</h2>
    <p>You can sign out, disconnect a wallet, or stop using Peak at any time. For data or deletion requests,
      see <a href="/legal/support">Support</a>.</p>

    <p class="muted">This draft does not describe every subprocessors’ practices. Final policy will name parties,
      retention, and rights under applicable law after counsel review.</p>
  `,
  });
}

export function termsHtml() {
  return page({
    title: "Terms of Use",
    heading: "Terms of Use",
    bodyHtml: `
    <p><strong>Draft only.</strong> These are placeholder terms for App Store URL fields.
      They are <em>not</em> a binding Terms of Service and are not legal advice. Replace with counsel-reviewed
      terms before App Store submission.</p>

    <h2>What Peak is</h2>
    <p>Peak helps you browse Polymarket markets and, when configured, place trades through Polymarket’s
      infrastructure. Peak does <strong>not</strong> operate an exchange and does not hold your funds except
      insofar as you use third-party wallets, Privy, or Polymarket deposit flows.</p>

    <h2>Your responsibilities</h2>
    <ul>
      <li>You must follow laws that apply to you, including any rules on prediction markets and crypto in your jurisdiction.</li>
      <li>Trading can result in loss of money. Peak provides software <strong>as-is</strong>, without warranties of any kind to the extent allowed by law.</li>
      <li>Polymarket’s own terms, risk disclosures, and market rules also apply when you use their services.</li>
      <li>Do not use Peak if you are prohibited from using Polymarket or similar products where you live.</li>
      <li>You are responsible for securing your devices, wallet keys, and account access.</li>
    </ul>

    <h2>Unofficial client</h2>
    <p>Peak is independent software. Features may break if Polymarket or Privy change their APIs.
      Peak may update, limit, or discontinue the app or API without notice.</p>

    <p class="muted">Questions: <a href="/legal/support">Support</a>.</p>
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
      <li><strong>Trading or deposits</strong> — Peak talks to Polymarket APIs. If an order or deposit looks stuck,
        check your wallet app, network (Polygon), and Polymarket status.</li>
      <li><strong>Sign-in</strong> — Peak uses Privy for auth. Try signing out and back in, or reconnecting your wallet.</li>
      <li><strong>App settings</strong> — Account and Settings in the Peak app have trading backend and legal links when configured.</li>
    </ul>
    <p class="muted">This page is hosted on the Peak API so App Store “Support URL” can use the same HTTPS host
      (<code>/legal/support</code>). Copy remains draft until a public support channel is finalized.</p>
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
