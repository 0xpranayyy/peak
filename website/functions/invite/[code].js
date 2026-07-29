/**
 * Cloudflare Pages Function for /invite/:code.
 *
 * A static-file rewrite via _redirects was tried first and was unreliable —
 * a wildcard match for a nonexistent path fell through to this project's SPA
 * fallback (root index.html) rather than the intended rewrite, confirmed by
 * a garbage path returning the same root page. Pages Functions handle a
 * dynamic path segment directly via context.params, with no rewrite-rule
 * precedence to fight. The code is interpolated server-side here rather than
 * parsed from the URL client-side, so it also renders correctly with
 * JavaScript disabled.
 */

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function onRequestGet({ params }) {
  const raw = String(params.code || "").trim();
  // Referral codes are generated from a fixed alphanumeric alphabet (see
  // referralStore.mjs) — reject anything else rather than reflect it.
  const code = /^[A-Za-z0-9]{1,16}$/.test(raw) ? raw.toUpperCase() : null;
  const display = code ? escapeHtml(code) : "Invalid code";

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>You're invited to Peak</title>
  <style>
    :root { color-scheme: light dark; --fg: #1a1a1a; --muted: #5c5c5c; --bg: #f7f7f5; --card: #fff; --accent: #0b6e4f; --line: #e3e3df; }
    @media (prefers-color-scheme: dark) {
      :root { --fg: #f2f2f0; --muted: #a8a8a4; --bg: #121411; --card: #1c1f1b; --accent: #3dba8c; --line: #2a2e29; }
    }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif;
      background: var(--bg); color: var(--fg); line-height: 1.6; }
    main { max-width: 26rem; margin: 0 auto; padding: 3.5rem 1.25rem 4rem; text-align: center; }
    .brand { font-size: 0.85rem; letter-spacing: 0.08em; text-transform: uppercase; color: var(--accent); font-weight: 700; }
    h1 { font-size: 1.5rem; margin: 0.6rem 0 0.5rem; font-weight: 650; }
    p { color: var(--muted); margin: 0 0 1.5rem; }
    .card { background: var(--card); border-radius: 12px; padding: 1.75rem; }
    .code { font-size: 1.6rem; font-weight: 700; letter-spacing: 0.12em; font-family: ui-monospace, monospace;
      background: color-mix(in srgb, var(--accent) 12%, transparent); border-radius: 8px;
      padding: 0.9rem; margin-bottom: 0.5rem; }
    .hint { font-size: 0.85rem; }
    .cta { display: inline-block; margin-top: 1.25rem; background: var(--accent); color: white;
      text-decoration: none; font-weight: 650; padding: 0.75rem 1.5rem; border-radius: 8px; opacity: 0.5; pointer-events: none; }
    footer { margin-top: 2rem; font-size: 0.85rem; }
    footer a { color: var(--muted); }
  </style>
</head>
<body>
  <main>
    <div class="brand">Peak</div>
    <h1>You've been invited</h1>
    <p>A friend wants you to try Peak, a native app for trading Polymarket prediction markets.</p>
    <div class="card">
      <div class="code">${display}</div>
      <p class="hint">Install Peak, then enter this code under Settings &rarr; Invite friends.</p>
      <!-- Filled in once Peak has a public App Store listing. -->
      <a class="cta" href="#">App Store link coming soon</a>
    </div>
    <footer>
      <a href="/legal/privacy">Privacy</a> &middot; <a href="/legal/terms">Terms</a> &middot; <a href="/legal/support">Support</a>
    </footer>
  </main>
</body>
</html>`;

  return new Response(html, {
    status: code ? 200 : 400,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}
