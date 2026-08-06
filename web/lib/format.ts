/** Display helpers. Kept in sync with `PeakFormat` on iOS so the two clients agree. */

/** 0.54 → "54¢". Binary markets price in cents, not percent, in the app's voice. */
export function cents(probability: number): string {
  return `${Math.round(probability * 100)}¢`;
}

/** 0.54 → "54%". Used where "chance" reads better than a price. */
export function percent(probability: number, digits = 0): string {
  return `${(probability * 100).toFixed(digits)}%`;
}

/** 1_240_000 → "$1.2M". Volume figures are large and only need a magnitude. */
export function compactUsd(value: number): string {
  if (!Number.isFinite(value) || value <= 0) return "$0";
  const units: [number, string][] = [
    [1_000_000_000, "B"],
    [1_000_000, "M"],
    [1_000, "K"],
  ];
  for (const [threshold, suffix] of units) {
    if (value >= threshold) {
      const scaled = value / threshold;
      return `$${scaled >= 100 ? Math.round(scaled) : scaled.toFixed(1)}${suffix}`;
    }
  }
  return `$${Math.round(value)}`;
}

/**
 * "Ends in 3 days" / "Ended". Deliberately coarse — an exact countdown implies a
 * precision the resolution process does not have.
 */
export function endsIn(isoDate: string | null): string | null {
  if (!isoDate) return null;
  const end = new Date(isoDate).getTime();
  if (!Number.isFinite(end)) return null;

  const deltaMs = end - Date.now();
  if (deltaMs <= 0) return "Ended";

  const days = Math.floor(deltaMs / 86_400_000);
  if (days >= 30) return `Ends in ${Math.floor(days / 30)}mo`;
  if (days >= 1) return `Ends in ${days}d`;
  const hours = Math.floor(deltaMs / 3_600_000);
  if (hours >= 1) return `Ends in ${hours}h`;
  return "Ends soon";
}
