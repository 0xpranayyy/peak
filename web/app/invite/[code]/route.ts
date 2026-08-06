/**
 * /invite/:code — ported from the Cloudflare Pages Function at
 * `website/functions/invite/[code].js`.
 *
 * It had to move: `next-on-pages` emits `_worker.js`, and Cloudflare Pages
 * refuses to run a `functions/` directory alongside one. Leaving the old file
 * in place would have silently killed every invite link the moment this app
 * took over the domain.
 *
 * Behaviour is deliberately unchanged, including the part that looks wrong at
 * first glance: an unreachable backend renders the invite as *valid*. Telling a
 * real invitee "this code doesn't work" because of a transient blip is a worse
 * failure than occasionally trusting a code we could not confirm. Only an
 * explicit `{ valid: false }` is treated as invalid.
 */

export const runtime = "edge";

const API_BASE =
  process.env.PEAK_API_URL ?? process.env.PEAK_API_BASE ?? "https://api.peakapp.site";

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function isLikelyValid(code: string): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 4000);
    const response = await fetch(
      `${API_BASE}/referral/validate/${encodeURIComponent(code)}`,
      { signal: controller.signal }
    );
    clearTimeout(timeout);

    if (!response.ok) return true; // backend hiccup — fail open
    const body = (await response.json()) as { valid?: boolean };
    return body.valid !== false;
  } catch {
    return true; // network error / timeout — fail open
  }
}

function page(opts: { heading: string; body: string; codeBlock: string }): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>You're invited to Peak</title>
  <style>
    :root { color-scheme: dark; --fg:#ededf2; --muted:#9a9aa8; --bg:#07070a; --card:#0d0d12; --accent:#3ddcbe; --line:#1c1c22; }
    *{box-sizing:border-box}
    body{margin:0;font-family:-apple-system,"SF Pro Display",ui-sans-serif,system-ui,"Segoe UI",sans-serif;background:var(--bg);color:var(--fg);line-height:1.6}
    main{max-width:30rem;margin:0 auto;padding:3.5rem 1.25rem 4rem;text-align:center}
    .logo{width:64px;height:64px;border-radius:15px;display:block;margin:0 auto .9rem;border:1px solid var(--line)}
    .brand{font-size:.85rem;letter-spacing:.1em;text-transform:uppercase;color:var(--accent);font-weight:700}
    h1{font-size:clamp(1.6rem,5vw,2.1rem);margin:.6rem 0;font-weight:800;letter-spacing:-.02em}
    p.lede{color:var(--muted);font-size:1.02rem;margin:0 0 1.75rem}
    .card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:1.75rem}
    .code{font-size:1.6rem;font-weight:700;letter-spacing:.14em;font-family:ui-monospace,"SF Mono",monospace;background:color-mix(in srgb,var(--accent) 14%,transparent);border-radius:10px;padding:.9rem;margin-bottom:.6rem}
    .hint{font-size:.85rem;color:var(--muted)}
    .cta{display:inline-block;margin-top:1.25rem;background:var(--accent);color:#06120f;text-decoration:none;font-weight:700;padding:.8rem 1.6rem;border-radius:10px}
    .browse{display:inline-block;margin-top:.9rem;color:var(--muted);text-decoration:none;font-size:.9rem}
    .browse:hover{color:var(--fg)}
    .steps{text-align:left;margin-top:2.5rem}
    .steps h2{font-size:.85rem;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);font-weight:650;margin-bottom:1.1rem;text-align:center}
    .step{display:flex;gap:.9rem;margin-bottom:1.25rem}
    .num{flex:0 0 auto;width:1.7rem;height:1.7rem;border-radius:50%;background:color-mix(in srgb,var(--accent) 16%,transparent);color:var(--accent);font-weight:700;font-size:.85rem;display:flex;align-items:center;justify-content:center}
    .step p{margin:0;font-size:.94rem}
    .step span.sub{display:block;color:var(--muted);font-size:.85rem;margin-top:.15rem}
    footer{margin-top:2.5rem;font-size:.85rem}
    footer a{color:var(--muted);text-decoration:none}
    footer a:hover{text-decoration:underline}
  </style>
</head>
<body>
  <main>
    <img class="logo" src="/peak-mark.png" width="64" height="64" alt="Peak app icon" />
    <div class="brand">Peak</div>
    <h1>${escapeHtml(opts.heading)}</h1>
    <p class="lede">${opts.body}</p>
    <div class="card">${opts.codeBlock}</div>
    <div class="steps">
      <h2>How it works</h2>
      <div class="step"><div class="num">1</div><p>Install Peak and sign in.<span class="sub">Email code, Apple, Google, or a connected wallet.</span></p></div>
      <div class="step"><div class="num">2</div><p>Enter the code above under Settings &rarr; Invite friends.<span class="sub">Takes a few seconds.</span></p></div>
      <div class="step"><div class="num">3</div><p>Make your first trade.<span class="sub">Once it clears, you and your friend both get 100 points &mdash; just for fun, no monetary value.</span></p></div>
    </div>
    <footer>
      <a href="/legal/privacy">Privacy</a> &middot; <a href="/legal/terms">Terms</a> &middot; <a href="/legal/support">Support</a>
    </footer>
  </main>
</body>
</html>`;
}

function html(body: string, status: number): Response {
  return new Response(body, {
    status,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ code: string }> }
) {
  const { code: raw } = await params;
  const trimmed = String(raw ?? "").trim();
  const wellFormed = /^[A-Za-z0-9]{1,16}$/.test(trimmed);
  const code = wellFormed ? trimmed.toUpperCase() : null;

  if (!code) {
    return html(
      page({
        heading: "Invalid invite link",
        body: "This link is missing a valid code. Ask your friend to resend it, or open Peak and enter a code manually.",
        codeBlock: `<div class="hint">No code found in this link.</div>`,
      }),
      400
    );
  }

  if (!(await isLikelyValid(code))) {
    return html(
      page({
        heading: "This code isn't valid",
        body: "We couldn't match this to an active Peak invite. It may be mistyped, or the friend who sent it should double-check their code.",
        codeBlock: `<div class="code" style="opacity:.5">${escapeHtml(code)}</div><div class="hint">This code doesn't match anyone.</div>`,
      }),
      404
    );
  }

  return html(
    page({
      heading: "You've been invited",
      body: "A friend wants you to try Peak, a native app for trading Polymarket prediction markets.",
      codeBlock: `
        <div class="code">${escapeHtml(code)}</div>
        <div class="hint">Your friend's invite code</div>
        <a class="browse" href="/markets">Browse live markets first &rarr;</a>
      `,
    }),
    200
  );
}
