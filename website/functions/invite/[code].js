/**
 * Cloudflare Pages Function for /invite/:code.
 *
 * Two things this does that a plain static page couldn't:
 *
 * 1. Confirms the code is real before saying "you've been invited". A static
 *    page can only check the URL's shape (right alphabet, right length) --
 *    it can't tell a well-formed but made-up code from one someone actually
 *    owns. This calls the backend's public GET /referral/validate/:code and
 *    only renders the invitation for a code that comes back true.
 *
 * 2. Fails open, not closed, if that check itself fails (network error,
 *    timeout, backend hiccup) -- shown as valid rather than invalid. The
 *    asymmetry is deliberate: telling a real invitee "this code doesn't
 *    work" because of a transient backend blip is a worse failure than
 *    occasionally trusting a code this check couldn't confirm. Only an
 *    explicit `{valid:false}` response is treated as invalid.
 */

const DEFAULT_API_BASE = "https://api.peakapp.site";

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function isLikelyValid(code, apiBase) {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 4000);
    const res = await fetch(`${apiBase}/referral/validate/${encodeURIComponent(code)}`, {
      signal: controller.signal,
    });
    clearTimeout(timeout);
    if (!res.ok) {
      console.error("validate fetch non-ok status", res.status, apiBase);
      return true; // backend hiccup — fail open, see module doc
    }
    const body = await res.json();
    return body.valid !== false;
  } catch (err) {
    console.error("validate fetch threw", apiBase, String(err), err?.cause ? String(err.cause) : "");
    return true; // network error / timeout — fail open, see module doc
  }
}

function page({ heading, body, codeBlock }) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>You're invited to Peak</title>
  <style>
    :root { color-scheme: light dark; --fg: #f2f2f0; --muted: #a8a8a4; --bg: #0a0a0b; --card: #16191a; --accent: #6bd1b8; --line: #24282a; }
    @media (prefers-color-scheme: light) {
      :root { --fg: #141a1c; --muted: #5c5c5c; --bg: #f9f9f8; --card: #fff; --accent: #298c7a; --line: #e3e3df; }
    }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: -apple-system, "SF Pro Display", ui-sans-serif, system-ui, Segoe UI, sans-serif;
      background: var(--bg); color: var(--fg); line-height: 1.6; }
    main { max-width: 30rem; margin: 0 auto; padding: 3.5rem 1.25rem 4rem; text-align: center; }
    .logo { width: 64px; height: 64px; border-radius: 15px; display: block; margin: 0 auto 0.9rem;
      border: 1px solid var(--line); box-shadow: 0 6px 20px rgba(0,0,0,0.28); }
    .brand { font-size: 0.85rem; letter-spacing: 0.1em; text-transform: uppercase; color: var(--accent); font-weight: 700; }
    h1 { font-size: clamp(1.6rem, 5vw, 2.1rem); margin: 0.6rem 0 0.6rem; font-weight: 700; letter-spacing: -0.01em; }
    p.lede { color: var(--muted); font-size: 1.02rem; margin: 0 0 1.75rem; }
    .card { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 1.75rem; }
    .code { font-size: 1.6rem; font-weight: 700; letter-spacing: 0.14em; font-family: ui-monospace, "SF Mono", monospace;
      background: color-mix(in srgb, var(--accent) 14%, transparent); border-radius: 10px;
      padding: 0.9rem; margin-bottom: 0.6rem; }
    .hint { font-size: 0.85rem; color: var(--muted); }
    .cta { display: inline-block; margin-top: 1.25rem; background: var(--accent); color: #06120f;
      text-decoration: none; font-weight: 700; padding: 0.8rem 1.6rem; border-radius: 10px;
      opacity: 0.55; pointer-events: none; }
    .steps { text-align: left; margin-top: 2.5rem; }
    .steps h2 { font-size: 0.85rem; letter-spacing: 0.06em; text-transform: uppercase;
      color: var(--muted); font-weight: 650; margin-bottom: 1.1rem; text-align: center; }
    .step { display: flex; gap: 0.9rem; margin-bottom: 1.25rem; }
    .step:last-child { margin-bottom: 0; }
    .num { flex: 0 0 auto; width: 1.7rem; height: 1.7rem; border-radius: 50%;
      background: color-mix(in srgb, var(--accent) 16%, transparent); color: var(--accent);
      font-weight: 700; font-size: 0.85rem; display: flex; align-items: center; justify-content: center; }
    .step p { margin: 0; color: var(--fg); font-size: 0.94rem; }
    .step span.sub { display: block; color: var(--muted); font-size: 0.85rem; margin-top: 0.15rem; }
    footer { margin-top: 2.5rem; font-size: 0.85rem; }
    footer a { color: var(--muted); text-decoration: none; }
    footer a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <main>
    <img class="logo" src="/PeakLogo.png" width="64" height="64" alt="Peak app icon" />
    <div class="brand">Peak</div>
    <h1>${escapeHtml(heading)}</h1>
    <p class="lede">${body}</p>
    <div class="card">
      ${codeBlock}
    </div>
    <div class="steps">
      <h2>How it works</h2>
      <div class="step">
        <div class="num">1</div>
        <p>Install Peak and sign in.<span class="sub">Email code, Apple, Google, or a connected wallet.</span></p>
      </div>
      <div class="step">
        <div class="num">2</div>
        <p>Enter the code above under Settings &rarr; Invite friends.<span class="sub">Takes a few seconds.</span></p>
      </div>
      <div class="step">
        <div class="num">3</div>
        <p>Make your first trade.<span class="sub">Once it clears, you and your friend both get 100 points &mdash; just for fun, no monetary value.</span></p>
      </div>
    </div>
    <footer>
      <a href="/legal/privacy">Privacy</a> &middot; <a href="/legal/terms">Terms</a> &middot; <a href="/legal/support">Support</a>
    </footer>
  </main>
</body>
</html>`;
}

export async function onRequestGet({ params, env }) {
  const apiBase = env.PEAK_API_BASE || DEFAULT_API_BASE;
  const raw = String(params.code || "").trim();
  const formatValid = /^[A-Za-z0-9]{1,16}$/.test(raw);
  const code = formatValid ? raw.toUpperCase() : null;

  if (!code) {
    return new Response(
      page({
        heading: "Invalid invite link",
        body: "This link is missing a valid code. Ask your friend to resend it, or open Peak and enter a code manually.",
        codeBlock: `<div class="hint">No code found in this link.</div>`,
      }),
      { status: 400, headers: { "content-type": "text/html; charset=utf-8" } }
    );
  }

  const valid = await isLikelyValid(code, apiBase);
  if (!valid) {
    return new Response(
      page({
        heading: "This code isn't valid",
        body: "We couldn't match this to an active Peak invite. It may be mistyped, or the friend who sent it should double-check their code.",
        codeBlock: `<div class="code" style="opacity:0.5">${escapeHtml(code)}</div><div class="hint">This code doesn't match anyone.</div>`,
      }),
      { status: 404, headers: { "content-type": "text/html; charset=utf-8" } }
    );
  }

  return new Response(
    page({
      heading: "You've been invited",
      body: "A friend wants you to try Peak, a native app for trading Polymarket prediction markets.",
      codeBlock: `
        <div class="code">${escapeHtml(code)}</div>
        <div class="hint">Your friend's invite code</div>
        <!-- Filled in once Peak has a public App Store listing. -->
        <a class="cta" href="#">App Store link coming soon</a>
      `,
    }),
    { status: 200, headers: { "content-type": "text/html; charset=utf-8" } }
  );
}
