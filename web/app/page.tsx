import { fetchEvents, type PeakEvent } from "@/lib/gamma";
import { MarketCard } from "@/components/MarketCard";

export const runtime = "edge";
// Rendered per request. `next-on-pages` does not support ISR, so `revalidate`
// would be a no-op on Cloudflare Pages anyway — and making it explicit keeps
// `next build` from needing live market data just to produce a bundle.
export const dynamic = "force-dynamic";

const LANDING = "https://peakapp.site";

/**
 * Landing. Marketing and live markets on one page, on one domain.
 *
 * The live strip is the argument: a static "trade prediction markets" pitch
 * asks the visitor to take our word for it, whereas six real markets with real
 * odds show what the product is before anyone installs anything.
 */
export default async function LandingPage() {
  const featured: PeakEvent[] = await fetchEvents({
    limit: 6,
    sort: "volume24hr",
  }).catch((): PeakEvent[] => []);

  return (
    <>
      <section className="hero hero--landing">
        <div className="shell">
          <p className="eyebrow">Polymarket, on Peak</p>
          <h1>Trade what you actually believe.</h1>
          <p className="lede">
            Peak is a fast client for Polymarket prediction markets. Browse live
            odds, sign in with Privy, and trade from your desktop — same backend
            as the iOS app.
          </p>
          <div className="hero__actions">
            <a className="btn btn--primary" href="/markets">
              Browse markets
            </a>
            <a className="btn" href="/portfolio">
              Open portfolio
            </a>
          </div>
        </div>
      </section>

      {featured.length > 0 ? (
        <section className="shell section">
          <div className="section__head">
            <h2>Trending now</h2>
            <a className="section__more" href="/markets">
              All markets →
            </a>
          </div>
          <div className="grid grid--tight">
            {featured.map((event) => (
              <MarketCard key={event.id} event={event} />
            ))}
          </div>
        </section>
      ) : null}

      <section className="shell section">
        <div className="section__head">
          <h2>Why Peak</h2>
        </div>
        <div className="pillars">
          <div className="pillar">
            <h3>Your wallet, your funds</h3>
            <p>
              Peak has no account of its own and never takes ownership of your
              money. Sign in with an embedded wallet and Peak never sees your
              private key.{" "}
              <a href="/legal/privacy#custody">How custody works →</a>
            </p>
          </div>
          <div className="pillar">
            <h3>Prices you can read</h3>
            <p>
              Live bid, ask and spread on the ticket before you order. A market
              at 70¢ prices a ~70% chance — not a promise, and it moves.
            </p>
          </div>
          <div className="pillar">
            <h3>Works where others don’t</h3>
            <p>
              Some networks block Polymarket outright. Peak routes market data
              through its own edge, so the app keeps working.
            </p>
          </div>
        </div>
      </section>

      <section className="shell section">
        <div className="closer">
          <h2>Ready when you are.</h2>
          <p>
            Browse without an account. Sign in with Privy to trade from the
            browser, or continue on iOS.
          </p>
          <div className="hero__actions">
            <a className="btn btn--primary" href="/markets">
              Browse markets
            </a>
            <a className="btn" href={LANDING} rel="noopener">
              About Peak / iOS
            </a>
          </div>
          <p className="risk">
            Prediction markets involve risk. Only trade money you can afford to
            lose. Peak is not affiliated with Polymarket, Inc.
          </p>
        </div>
      </section>
    </>
  );
}
