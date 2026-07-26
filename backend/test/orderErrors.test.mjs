import { test } from "node:test";
import assert from "node:assert/strict";
import { mapOrderError, isImportWalletError, mapCashError } from "../orderErrors.mjs";

/**
 * These map raw CLOB/Privy text into what a user reads and what the client
 * branches on. The codes are a contract: the iOS app keys off them, so a
 * silent change here shows up as the wrong screen rather than an error.
 */

test("no-fill covers every phrasing CLOB actually returns", () => {
  for (const raw of [
    "order couldn't be fully filled. FOK orders are fully filled or killed.",
    "no match found",
    "FOK order killed",
  ]) {
    assert.equal(mapOrderError(raw).code, "no_fill", `missed: ${raw}`);
  }
});

test("insufficient funds includes the balance when known", () => {
  const withBalance = mapOrderError("not enough balance", { balanceUSD: 4.2 });
  assert.equal(withBalance.code, "insufficient_funds");
  assert.match(withBalance.error, /4\.20/, "the user should see what they actually have");

  // Must not print "$null" when the balance could not be read.
  const without = mapOrderError("not enough balance");
  assert.equal(without.code, "insufficient_funds");
  assert.doesNotMatch(without.error, /null|undefined|NaN/);
});

test("market closed and builder-missing are distinguished", () => {
  assert.equal(mapOrderError("market is not accepting orders").code, "market_closed");
  const builder = mapOrderError("builder credentials missing");
  assert.equal(builder.code, "builder_not_ready");
  assert.equal(builder.status, 503, "our misconfiguration is a 5xx, not the user's 4xx");
});

test("an explicit code hint wins over the raw text", () => {
  assert.equal(
    mapOrderError("some unrelated upstream noise", { code: "import_wallet_required" }).code,
    "import_wallet_required"
  );
});

test("unknown text still yields a usable message and a 4xx", () => {
  const r = mapOrderError("frobnicator exploded");
  assert.ok(r.error && r.error.length > 0);
  assert.ok(r.code);
  assert.ok(r.status >= 400 && r.status < 600);
});

test("empty and nullish input do not throw or leak", () => {
  for (const raw of ["", null, undefined]) {
    const r = mapOrderError(raw);
    assert.ok(r.error.length > 0, "must never render an empty alert");
    assert.doesNotMatch(r.error, /null|undefined/);
  }
});

test("import-wallet detection matches the shapes Privy returns", () => {
  assert.ok(isImportWalletError({ code: "import_wallet_required" }));
  assert.ok(isImportWalletError({ message: "import the private key for this wallet" }));
  assert.ok(!isImportWalletError({ message: "not enough balance" }));
  assert.ok(!isImportWalletError(null), "nullish must not crash the caller");
});

test("cash errors separate 'needs import' from 'auth failed'", () => {
  const needsImport = mapCashError({ code: "import_wallet_required" });
  assert.equal(needsImport.needsImport, true);

  // A JWT rejection is an auth failure, not a missing key — telling the user to
  // re-import would send them to redo work that is already done.
  const authFailed = mapCashError({ message: "Invalid JWT token provided" });
  assert.equal(authFailed.cashErrorCode, "wallet_auth_failed");
  assert.equal(authFailed.needsImport, false);
});
