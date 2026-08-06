"use client";

import { useState } from "react";
import type { Market } from "@/lib/gamma";
import { TradeTicket } from "@/components/TradeTicket";

export function EventTradePanel({ markets }: { markets: Market[] }) {
  const [index, setIndex] = useState(0);
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
      <TradeTicket key={market.id} market={market} />
    </div>
  );
}
