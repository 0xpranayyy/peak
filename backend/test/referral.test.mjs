import { test } from "node:test";
import assert from "node:assert/strict";
import os from "node:os";
import path from "node:path";

// Must be set before the module is imported — it opens its DB at import time.
process.env.PEAK_REFERRAL_STORE = path.join(os.tmpdir(), `peak-referral-test-${Date.now()}.db`);

const {
  getOrCreateCode,
  redeemCode,
  awardMilestone,
  getBalance,
  getHistory,
  ReferralError,
  REFERRER_BONUS,
  REFERRED_BONUS,
} = await import("../referralStore.mjs");

/**
 * Points here have no redeemable value (see the Terms), but the ledger still
 * has to be exactly right — a wrong balance is a support ticket and a broken
 * trust signal, even for something cosmetic. Every test uses its own user IDs
 * so it doesn't depend on --test's execution order.
 */

test("getOrCreateCode is idempotent per user", () => {
  const code1 = getOrCreateCode("user-idempotent-1");
  const code2 = getOrCreateCode("user-idempotent-1");
  assert.equal(code1, code2, "the same user must always get the same code back");
});

test("different users get different codes", () => {
  const a = getOrCreateCode("user-distinct-a");
  const b = getOrCreateCode("user-distinct-b");
  assert.notEqual(a, b);
});

test("codes avoid visually ambiguous characters", () => {
  const code = getOrCreateCode("user-alphabet-check");
  for (const bad of ["0", "O", "1", "I", "L"]) {
    assert.ok(!code.includes(bad), `code ${code} contains ambiguous character ${bad}`);
  }
});

test("cannot redeem your own code", () => {
  getOrCreateCode("user-self-referral");
  const code = getOrCreateCode("user-self-referral");
  assert.throws(
    () => redeemCode("user-self-referral", code),
    (err) => err instanceof ReferralError && err.code === "self_referral"
  );
});

test("an unknown code is rejected clearly", () => {
  assert.throws(
    () => redeemCode("user-unknown-code", "NOTAREALCODE"),
    (err) => err instanceof ReferralError && err.code === "code_not_found"
  );
});

test("a valid redemption links the referred user to the referrer", () => {
  const referrerCode = getOrCreateCode("user-referrer-1");
  const result = redeemCode("user-referred-1", referrerCode);
  assert.equal(result.referrerId, "user-referrer-1");
});

test("redeeming twice is rejected, not silently reapplied", () => {
  const referrerCode = getOrCreateCode("user-referrer-2");
  redeemCode("user-referred-2", referrerCode);

  const otherCode = getOrCreateCode("user-referrer-3");
  assert.throws(
    () => redeemCode("user-referred-2", otherCode),
    (err) => err instanceof ReferralError && err.code === "already_referred"
  );
});

test("awardMilestone pays both sides when a referral exists", () => {
  const referrerCode = getOrCreateCode("user-referrer-4");
  redeemCode("user-referred-4", referrerCode);

  const result = awardMilestone("user-referred-4");
  assert.equal(result.awarded, true);
  assert.equal(getBalance("user-referrer-4"), REFERRER_BONUS);
  assert.equal(getBalance("user-referred-4"), REFERRED_BONUS);
});

test("awardMilestone is a no-op for a user with no referrer", () => {
  getOrCreateCode("user-no-referrer");
  const result = awardMilestone("user-no-referrer");
  assert.equal(result.awarded, false);
  assert.equal(getBalance("user-no-referrer"), 0);
});

test("awardMilestone does not double-pay on a second call", () => {
  const referrerCode = getOrCreateCode("user-referrer-5");
  redeemCode("user-referred-5", referrerCode);

  awardMilestone("user-referred-5");
  const second = awardMilestone("user-referred-5");

  assert.equal(second.awarded, false, "the bonus was already paid; a retry must not pay it again");
  assert.equal(getBalance("user-referrer-5"), REFERRER_BONUS, "not 2x REFERRER_BONUS");
  assert.equal(getBalance("user-referred-5"), REFERRED_BONUS, "not 2x REFERRED_BONUS");
});

test("awardMilestone called for an unknown user does not throw", () => {
  assert.doesNotThrow(() => awardMilestone("user-never-created"));
});

test("getBalance sums every ledger entry for a user", () => {
  const referrerCode = getOrCreateCode("user-referrer-6");
  redeemCode("user-referred-6a", referrerCode);
  redeemCode("user-referred-6b", referrerCode);
  awardMilestone("user-referred-6a");
  awardMilestone("user-referred-6b");

  assert.equal(getBalance("user-referrer-6"), REFERRER_BONUS * 2);
});

test("getHistory returns entries newest-first and respects the limit", () => {
  const referrerCode = getOrCreateCode("user-referrer-7");
  const friends = ["7a", "7b", "7c"];
  for (const f of friends) {
    redeemCode(`user-referred-${f}`, referrerCode);
    awardMilestone(`user-referred-${f}`);
  }

  const history = getHistory("user-referrer-7", 2);
  assert.equal(history.length, 2, "limit must be honored");
  assert.ok(
    history[0].created_at >= history[1].created_at,
    "must be ordered newest-first"
  );
});

test("getBalance and getHistory are empty for a user who has never earned anything", () => {
  assert.equal(getBalance("user-nobody-1234"), 0);
  assert.deepEqual(getHistory("user-nobody-1234"), []);
});
