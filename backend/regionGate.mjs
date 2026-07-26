/**
 * Region and edge-origin decisions, split out so they can be tested.
 *
 * These previously lived inline in server.mjs, which starts a listener on
 * import and so cannot be loaded from a test. A mistake in either function is
 * an outage or a compliance hole rather than a cosmetic bug, so they should not
 * be the untestable part.
 */
import crypto from "crypto";

export function timingSafeEqualStrings(a, b) {
  const bufA = Buffer.from(String(a ?? ""));
  const bufB = Buffer.from(String(b ?? ""));
  if (bufA.length !== bufB.length) {
    // Compare equal-length buffers anyway so failure timing does not depend on
    // the length mismatch itself.
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

/**
 * Did this request come through the Cloudflare Worker?
 *
 * Fail-safe by design: with no secret configured this returns true, so setting
 * the secret on only one side cannot lock every user out mid-rollout.
 */
export function isFromEdge(headers, secret) {
  if (!secret) return true;
  return timingSafeEqualStrings(headers?.["x-peak-edge-secret"] || "", secret);
}

/** Normalised region verdict from the header the Worker stamps. */
export function regionStatus(headers) {
  const raw = String(headers?.["x-peak-region-status"] || "").toLowerCase();
  if (raw === "blocked" || raw === "close_only" || raw === "allowed") return raw;
  return "unknown";
}

/**
 * Should this order be refused on region grounds?
 *
 * `opening` is true for a BUY. Blocked regions may neither open nor close;
 * close-only regions may close but not open — so a user there can still exit a
 * position they already hold.
 *
 * Unknown is allowed: the request may legitimately predate the header, and CLOB
 * still enforces server-side. Over-blocking real users is the worse error.
 */
export function shouldRefuseForRegion(headers, { opening }) {
  const status = regionStatus(headers);
  return status === "blocked" || (opening && status === "close_only");
}
