import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "crypto";

// Mirrors the backend's helpers so the fail-safe rule is pinned.
function timingSafeEqualStrings(a, b) {
  const A = Buffer.from(String(a ?? "")), B = Buffer.from(String(b ?? ""));
  if (A.length !== B.length) { crypto.timingSafeEqual(A, A); return false; }
  return crypto.timingSafeEqual(A, B);
}
const isFromEdge = (secret, header) =>
  !secret ? true : timingSafeEqualStrings(header || "", secret);

test("unset secret changes nothing — cannot lock users out mid-rollout", () => {
  assert.equal(isFromEdge(undefined, undefined), true);
  assert.equal(isFromEdge("", "anything"), true);
});

test("configured secret admits only the matching header", () => {
  assert.equal(isFromEdge("s3cret", "s3cret"), true);
  assert.equal(isFromEdge("s3cret", "wrong"), false);
  assert.equal(isFromEdge("s3cret", undefined), false, "a direct origin call sends none");
});

test("length mismatch does not throw", () => {
  assert.equal(isFromEdge("longsecret", "x"), false);
});
