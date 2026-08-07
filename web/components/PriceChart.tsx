"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import {
  HISTORY_INTERVALS,
  fetchPriceHistory,
  type HistoryInterval,
  type PricePoint,
} from "@/lib/clob";
import { cents } from "@/lib/format";

type Props = {
  tokenID: string | null;
  /** Live mid/last to pin on the tip when history exists. */
  livePrice?: number | null;
};

/**
 * Midpoint price series from CLOB `/prices-history` via edge.
 * SVG area — no candle invention, empty when Polymarket has no series.
 */
export function PriceChart({ tokenID, livePrice }: Props) {
  const [interval, setInterval] = useState<HistoryInterval>("1d");
  const [points, setPoints] = useState<PricePoint[] | null>(null);
  const [hover, setHover] = useState<{ i: number; x: number; y: number } | null>(
    null
  );
  const svgRef = useRef<SVGSVGElement>(null);
  const plotRef = useRef<HTMLDivElement>(null);
  const gradId = useId().replace(/:/g, "");

  /**
   * The viewBox tracks the plot's real pixel box instead of a fixed 640×220.
   * With a fixed aspect the SVG could only ever letterbox inside its panel, and
   * next to a full-height order book that left a third of the card empty. One
   * unit of the viewBox is now one CSS pixel, which also makes the hover
   * hit-test exact rather than approximately right.
   */
  const [box, setBox] = useState({ w: 640, h: 220 });

  useEffect(() => {
    const node = plotRef.current;
    if (!node || typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect;
      if (width < 1 || height < 1) return;
      setBox((prev) =>
        Math.abs(prev.w - width) < 1 && Math.abs(prev.h - height) < 1
          ? prev
          : { w: Math.round(width), h: Math.round(height) }
      );
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, [points]);

  useEffect(() => {
    if (!tokenID) {
      setPoints([]);
      return;
    }
    let cancelled = false;
    setPoints(null);
    (async () => {
      const next = await fetchPriceHistory(tokenID, interval);
      if (!cancelled) setPoints(next);
    })();
    return () => {
      cancelled = true;
    };
  }, [tokenID, interval]);

  const series = useMemo(() => {
    if (!points || points.length === 0) return [];
    // Drop obvious bad tip spikes (pinned 0) that warp the chart — iOS does this.
    let cleaned = points.filter((p) => p.p > 0.001 && p.p < 0.999);
    if (cleaned.length < 2) cleaned = points;
    if (
      livePrice != null &&
      livePrice > 0 &&
      livePrice < 1 &&
      cleaned.length > 0
    ) {
      const last = cleaned[cleaned.length - 1];
      return [...cleaned.slice(0, -1), { t: last.t, p: livePrice }];
    }
    return cleaned;
  }, [points, livePrice]);

  const layout = useMemo(() => {
    const W = box.w;
    const H = box.h;
    const padL = 8;
    const padR = 44;
    const padT = 16;
    const padB = 28;
    if (series.length < 2) {
      return { W, H, padL, padR, padT, padB, path: "", area: "", min: 0, max: 1, xs: [] as number[], ys: [] as number[] };
    }
    let min = Math.min(...series.map((p) => p.p));
    let max = Math.max(...series.map((p) => p.p));
    const span = Math.max(0.02, max - min);
    min = Math.max(0, min - span * 0.12);
    max = Math.min(1, max + span * 0.12);
    if (max - min < 0.02) {
      const mid = (min + max) / 2;
      min = Math.max(0, mid - 0.01);
      max = Math.min(1, mid + 0.01);
    }
    const innerW = W - padL - padR;
    const innerH = H - padT - padB;
    const xs: number[] = [];
    const ys: number[] = [];
    const coords = series.map((p, i) => {
      const x = padL + (i / (series.length - 1)) * innerW;
      const y = padT + (1 - (p.p - min) / (max - min)) * innerH;
      xs.push(x);
      ys.push(y);
      return `${x.toFixed(2)},${y.toFixed(2)}`;
    });
    const path = `M ${coords.join(" L ")}`;
    const area = `${path} L ${xs[xs.length - 1].toFixed(2)},${(H - padB).toFixed(2)} L ${xs[0].toFixed(2)},${(H - padB).toFixed(2)} Z`;
    return { W, H, padL, padR, padT, padB, path, area, min, max, xs, ys };
  }, [series, box]);

  const last = series.length ? series[series.length - 1] : null;
  const first = series.length ? series[0] : null;
  const delta =
    last && first && first.p > 0 ? last.p - first.p : null;
  const up = delta != null ? delta >= 0 : true;

  function onMove(e: React.MouseEvent<SVGSVGElement>) {
    if (series.length < 2 || !svgRef.current) return;
    const rect = svgRef.current.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width) * layout.W;
    let best = 0;
    let bestDist = Infinity;
    for (let i = 0; i < layout.xs.length; i++) {
      const d = Math.abs(layout.xs[i] - x);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    setHover({ i: best, x: layout.xs[best], y: layout.ys[best] });
  }

  const hoverPoint = hover ? series[hover.i] : null;

  return (
    <div className="chart">
      <div className="chart__head">
        <div className="chart__title">
          <span className="chart__label">Price</span>
          {last ? (
            <span className={`chart__last ${up ? "is-up" : "is-down"}`}>
              {cents(last.p)}
              {delta != null ? (
                <span className="chart__delta">
                  {delta >= 0 ? "+" : ""}
                  {Math.round(delta * 100)}¢
                </span>
              ) : null}
            </span>
          ) : (
            <span className="chart__last">—</span>
          )}
        </div>
        <div className="chart__intervals" role="group" aria-label="Chart interval">
          {HISTORY_INTERVALS.map((opt) => (
            <button
              key={opt.key}
              type="button"
              className={interval === opt.key ? "seg seg--xs seg--on" : "seg seg--xs"}
              onClick={() => setInterval(opt.key)}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {points == null ? (
        <div className="chart__empty">Loading chart…</div>
      ) : series.length < 2 ? (
        <div className="chart__empty">No price history for this outcome yet.</div>
      ) : (
        <div className="chart__plot" ref={plotRef}>
          <svg
            ref={svgRef}
            viewBox={`0 0 ${layout.W} ${layout.H}`}
            className="chart__svg"
            onMouseMove={onMove}
            onMouseLeave={() => setHover(null)}
            role="img"
            aria-label="Outcome price history"
          >
            <defs>
              <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
                <stop
                  offset="0%"
                  stopColor={up ? "var(--buy)" : "var(--sell)"}
                  stopOpacity="0.28"
                />
                <stop
                  offset="100%"
                  stopColor={up ? "var(--buy)" : "var(--sell)"}
                  stopOpacity="0"
                />
              </linearGradient>
            </defs>
            {/* Y ticks */}
            {[0, 0.5, 1].map((t) => {
              const p = layout.min + t * (layout.max - layout.min);
              const y =
                layout.padT +
                (1 - t) * (layout.H - layout.padT - layout.padB);
              return (
                <g key={t}>
                  <line
                    x1={layout.padL}
                    x2={layout.W - layout.padR}
                    y1={y}
                    y2={y}
                    className="chart__grid"
                  />
                  <text
                    x={layout.W - layout.padR + 6}
                    y={y + 3}
                    className="chart__tick"
                  >
                    {Math.round(p * 100)}¢
                  </text>
                </g>
              );
            })}
            <path d={layout.area} fill={`url(#${gradId})`} />
            <path
              d={layout.path}
              fill="none"
              stroke={up ? "var(--buy)" : "var(--sell)"}
              strokeWidth="2"
              strokeLinejoin="round"
              strokeLinecap="round"
            />
            {hover && hoverPoint ? (
              <>
                <line
                  x1={hover.x}
                  x2={hover.x}
                  y1={layout.padT}
                  y2={layout.H - layout.padB}
                  className="chart__cross"
                />
                <circle
                  cx={hover.x}
                  cy={hover.y}
                  r="4"
                  fill={up ? "var(--buy)" : "var(--sell)"}
                  stroke="var(--ink)"
                  strokeWidth="2"
                />
              </>
            ) : null}
          </svg>
          {hoverPoint ? (
            <div className="chart__tooltip mono">
              {cents(hoverPoint.p)}
              <span>
                {new Date(hoverPoint.t * 1000).toLocaleString(undefined, {
                  month: "short",
                  day: "numeric",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </span>
            </div>
          ) : null}
        </div>
      )}
    </div>
  );
}
