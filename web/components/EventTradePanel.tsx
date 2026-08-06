"use client";

import { useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import type { Market } from "@/lib/gamma";
import { TradeTicket } from "@/components/TradeTicket";

export function EventTradePanel({ markets }: { markets: Market[] }) {
  const searchParams = useSearchParams();
  const preferredOutcome = searchParams.get("outcome") ?? undefined;
  const preferredAsset =
    searchParams.get("asset") ?? searchParams.get("tokenID") ?? undefined;
  const initialSide =
    searchParams.get("side")?.toUpperCase() === "SELL" ? ("SELL" as const) : ("BUY" as const);
  const sharesParam = Number(searchParams.get("shares"));
  const initialShares =
    Number.isFinite(sharesParam) && sharesParam > 0 ? sharesParam : undefined;

  const preferredIndex = useMemo(() => {
    if (preferredAsset) {
      const byToken = markets.findIndex((m) => m.clobTokenIds.includes(preferredAsset));
      if (byToken >= 0) return byToken;
    }
    if (!preferredOutcome) return 0;
    const idx = markets.findIndex((m) => m.outcomes.includes(preferredOutcome));
    return idx >= 0 ? idx : 0;
  }, [markets, preferredAsset, preferredOutcome]);

  const [index, setIndex] = useState(preferredIndex);
  const market = markets[Math.min(index, markets.length - 1)];
  if (!market) return null;

  return (
    <div className="detail__aside">
      {markets.length > 1 ? (
        <label className="field field--select">
          <span>Market</span>
          <select
            value={index}
            onChange={(e) => setIndex(Number(e.target.value))}
          >
            {markets.map((m, i) => (
              <option key={m.id} value={i}>
                {m.question.length > 72 ? `${m.question.slice(0, 72)}…` : m.question}
              </option>
            ))}
          </select>
        </label>
      ) : null}
      <TradeTicket
        key={`${market.id}-${initialSide}-${preferredAsset ?? preferredOutcome ?? ""}`}
        market={market}
        preferredOutcome={preferredOutcome}
        preferredTokenID={preferredAsset}
        initialSide={initialSide}
        initialShares={initialShares}
      />
    </div>
  );
}
