# Changelog

Notable changes to Peak. Newest first.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dates
are the day the work landed on `web-client`, not the day it deployed — deploys
are called out explicitly where they happened.

Sections used: **Added**, **Changed**, **Fixed**, **Removed**. "Fixed" entries
name the actual failure, not just the file, because that is the part worth
remembering six months from now.

---

## [Unreleased] — web client

### Added

- **A real order confirmation.** Every result used to be one line of small text
  reading "Order submitted" — the same sentence whether the order filled,
  partially filled, or is sitting unmatched on the book. It now shows what
  actually happened, in four distinct states: **filled**, **partially filled**,
  **on the book** (nothing bought yet), and **submitted** when CLOB does not say
  enough to classify it. Fill sizes are only shown when they can be trusted;
  where they cannot, the wording degrades to the vaguer answer rather than
  inventing one.
- **Installable as an app.** A web manifest, iOS standalone meta, maskable
  icons, and home-screen shortcuts to Markets, Positions and Watchlist. Launched
  from the home screen it opens at `/markets` with no browser chrome. Safe-area
  handling keeps the nav clear of the notch and the footer clear of the home
  indicator.
- **A Max button on the sell side, backed by the real holding.** Selling used to
  offer fixed share presets (5/10/25/50/100) and a free-text box, so closing a
  position meant remembering how many shares you owned or going to look it up.
  The ticket now reads your actual position for the selected outcome and offers
  **25% · 50% · 75% · Max**, a `Max` shortcut on the field label, and a line
  showing what you hold and roughly what the sale is worth. Signed out, or with
  no position, it falls back to the old fixed presets.
- **An oversell guard.** Asking for more shares than you hold is caught before
  the order is sent, instead of round-tripping to the backend and coming back as
  `insufficient_shares`.
- **Two-level market taxonomy.** Every top-level section now has subsections:
  Sports splits into Soccer, Basketball, NFL, Baseball, Cricket, Tennis,
  Esports, UFC, Golf, Rugby, NHL and F1; Crypto into Bitcoin/Ethereum/Solana/
  XRP/Prices; and so on for Politics, Elections, Finance, Tech, AI, Culture,
  Science and World. A second chip row appears only inside a section that has
  one. Sub-slugs are globally unique, so browsing stays on a single `?tag=`
  parameter and every existing link keeps working.
- **Incremental loading.** "Load more markets" appends to the feed instead of
  replacing it. Nothing is prefetched on scroll — the feed only fetches what you
  ask for.
- **Real result counts.** The header shows "43 of 272" from Gamma's own totals.
- **Sign-in sheet** in front of Privy, explaining what an account is for, that
  browsing needs none, and who holds the funds. Each method opens Privy already
  on that method. Contextual headings per entry point (nav / trade ticket /
  positions).
- **First-run welcome** on the markets feed: how to read the odds, where trading
  happens, and where the money sits. Dismissed once, gone for good.
- **Dark/light theme switch** ported from peakapp.site — the sun/moon arcing
  over the Peak ridge, with the same view-transition sweep. Follows the OS until
  you pick a side.
- **Event artwork** on market rows, with a fixed-size placeholder so rows below
  an artless event stay aligned.
- This changelog.

### Changed

- **Multi-market rows show a real outcome**, not a bare leg count — "No change
  64%", "JD Vance 21%" instead of "28 markets", via a shared `headlineOdds`
  helper.
- **Ladder markets no longer render as a wall of 100%.** `headlineOdds` picks
  the cheapest leg the market still favours, falling back to the front-runner
  when it favours nothing. "Bitcoin above ___" lists a strike per level with
  every strike under spot at 100%, so ranking on price alone always surfaced a
  foregone one; the new rule surfaces the strike nearest the money — "above
  64,000 · 100%" — which is the one number on the row that says where Bitcoin
  is. Fields of rivals are unaffected. It still selects among real legs and
  shows each one's real price against its own name.
- **Event leg chips use `groupItemTitle`** rather than `question`, which repeats
  the full event title on every leg — the strip used to read as the same
  truncated sentence five times over.
- **The trade ticket opens on the highest-priced leg.** It opened on the first
  tradable one, which Gamma orders arbitrarily; that regularly meant a 1¢ tail
  outcome.
- **Order book trimmed to 8 levels a side.** Cumulative totals are still
  computed over the whole book — the trim is presentation, not arithmetic.
- **The event header moved into the page grid**, so on a phone (where the ticket
  is hoisted above the chart) you read what you are trading before you see the
  buy button.
- **Every colour is a theme token**, with a `[data-theme="light"]` block. Light
  mode uses a darker teal (`#0d9488`) — the dark-mode accent fails contrast on
  white.
- **The Privy modal follows the app theme** instead of being pinned to dark.
- Market rows are separated cards with hover lift and a probability bar; pill
  buttons, chips, tabs and inputs throughout.
- Feed requests use Gamma's `/events/pagination` endpoint for a truthful
  `hasMore`, and carry an `AbortSignal` so a slow request for an abandoned
  filter cannot land on top of a newer one.

### Fixed

- **The "Culture" chip had always shown an empty list.** It filtered on a
  `culture` tag that exists upstream and matches nothing; Polymarket files that
  content under `pop-culture`.
- **The order book never loaded in a background tab.** Both `OrderBookPanel` and
  `TradeTicket` skipped their *initial* fetch when `document.hidden`, not just
  the poll, so a page opened in a background tab sat on "Loading book…" and
  quoted with no bid/ask until it was focused.
- **The sign-in dialog rendered clipped inside the 60px nav bar.** The masthead
  sets `backdrop-filter`, which makes it a containing block for
  `position: fixed`, so the scrim's `inset: 0` resolved to the header. Now
  portalled to `<body>`.
- **Market rows pushed the page into horizontal scroll on phones.** The odds
  column was an `auto` grid track and the leading-outcome caption is `nowrap`,
  so a long leg name sized the track to the untruncated string.
- **The price chart could only letterbox inside its card**, leaving a third of
  the panel empty next to a full-height order book — it had a fixed 640×220
  viewBox. It tracks its container now, which also makes the hover hit-test
  exact rather than approximate.
- **"Next page" appeared on the last page** whenever the final window happened
  to be exactly full, and counts read "24+" when 24 was the whole set. Both came
  from guessing at `hasMore`; upstream reports it.
- Paging by offset counted *filtered* rows, so windows containing finished games
  would re-request rows already dropped and stall.
- A modal taller than the viewport could not be scrolled to its top — the scrim
  centred with `align-items` instead of `margin: auto`.
- Opening the sign-in sheet focused its close button, i.e. the app suggesting
  you leave. Focus goes to the dialog.
- Event tab titles rendered the raw slug ("fed decision in september 762").
- **The watchlist fired one full-event request per saved market, in parallel.**
  Each of those carries every nested leg of its event, so a modest watchlist
  opened with tens of megabytes in flight at once. Gamma accepts a repeated `id`
  parameter — it is one chunked request now.
- The geo probe had no timeout, the only call in the client without one. A hung
  edge left `geo` null for the whole session instead of falling back to the open
  default.
- Two call sites passed React's `MouseEvent` straight into Privy's `login`.

### Removed

- Numbered page links on the markets feed, replaced by incremental loading.
- `fetchEventById`, superseded by the batched `fetchEventsByIds`.

### Known, not yet fixed

- **The feed's payload is far larger than what it renders.** Gamma inlines every
  leg of every event, so one 24-row window is ~3.2 MB of JSON — three of those
  rows are 128-leg election markets. Compression hides most of it (~340 KB over
  the wire), and the remaining cost is parse time on low-end phones rather than
  bandwidth. Gamma ignores every field-selection parameter tried
  (`fields`, `include_markets`, …), so trimming has to happen in the edge Worker
  — which also serves iOS, so it wants its own change and deploy rather than
  riding along with a web commit.

---

## Earlier

Before this file existed, changes were recorded only in commit messages. See
`git log` for the iOS client, backend, edge Worker and landing page history —
notably the referral system, the Polymarket leaderboard, the legal pages, and
the move of `/invite/:code` from a Pages Function to a Next route.
