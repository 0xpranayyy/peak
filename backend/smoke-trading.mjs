/**
 * Smoke checks that don't need user secrets / private keys.
 * Verifies CLOB AssetType shape, signature_type mapping, Privy viem helper,
 * and friendly error mapping (no raw typed_data JSON).
 *
 * Run: node smoke-trading.mjs
 */
import { AssetType, SignatureTypeV2 } from "@polymarket/clob-client-v2";
import { createViemAccount } from "@privy-io/node/viem";
import { signatureTypeFromWalletName } from "./tradingSetup.mjs";
import { mapOrderError, mapCashError, isImportWalletError } from "./orderErrors.mjs";
import { buildAuthorizationContext } from "./privyViemAccount.mjs";

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

assert(AssetType.COLLATERAL === "COLLATERAL", "AssetType.COLLATERAL");
assert(AssetType.CONDITIONAL === "CONDITIONAL", "AssetType.CONDITIONAL");

const balanceParams = { asset_type: AssetType.COLLATERAL, signature_type: 3 };
assert(balanceParams.asset_type === "COLLATERAL", "balance params asset_type");
assert(balanceParams.signature_type === 3, "balance params signature_type");

assert(signatureTypeFromWalletName("EOA", 3) === 0, "EOA → 0");
assert(signatureTypeFromWalletName("POLY_PROXY", 3) === 1, "PROXY → 1");
assert(signatureTypeFromWalletName("GNOSIS_SAFE", 3) === 2, "SAFE → 2");
assert(signatureTypeFromWalletName("DEPOSIT_WALLET", 0) === 3, "DEPOSIT → 3");
assert(SignatureTypeV2.POLY_1271 != null, "SignatureTypeV2.POLY_1271 present");

assert(typeof createViemAccount === "function", "createViemAccount export");

const importMapped = mapOrderError("boom", { code: "import_wallet_required" });
assert(importMapped.code === "import_wallet_required", "import code");
assert(!importMapped.error.includes("{"), "import copy not JSON");

const typed = mapOrderError(
  '{"error":"invalid_data","message":"params required","unrecognized_keys":["typed_data"]}'
);
assert(typed.code === "sign_failed" || typed.code === "order_failed", "typed_data mapped");
assert(!typed.error.includes("typed_data"), "no typed_data in user copy");
assert(!typed.error.startsWith("{"), "no raw JSON in user copy");

const allowance = mapOrderError("not enough balance / allowance");
assert(allowance.code === "insufficient_funds", "allowance → insufficient_funds");

const cash = mapCashError({ code: "import_wallet_required", safeMessage: "Import the private key" });
assert(cash.needsImport === true, "cash needsImport");
assert(cash.cashErrorCode === "import_wallet_required", "cashErrorCode");

assert(isImportWalletError({ code: "import_wallet_required" }), "isImportWalletError");

const authFail = mapOrderError(
  '401 {"error":"No valid authorization keys or user signing keys available"}'
);
assert(authFail.code === "wallet_auth_failed", "wallet_auth_failed code");
assert(!authFail.error.includes("401"), "no status code in copy");
assert(!authFail.error.includes("{"), "no raw JSON in auth copy");
assert(authFail.error.toLowerCase().includes("authorize"), "auth copy mentions authorize");

const cashAuth = mapCashError({
  code: "wallet_auth_failed",
  message: "No valid authorization keys or user signing keys available",
});
assert(cashAuth.cashErrorCode === "wallet_auth_failed", "cash wallet_auth_failed");
assert(!cashAuth.cashError.includes("{"), "cash auth copy not JSON");

const ctxBoth = buildAuthorizationContext({ authorizationKey: "k", userJwt: "jwt" });
assert(ctxBoth.user_jwts?.[0] === "jwt", "auto prefers jwt alone");
assert(!ctxBoth.authorization_private_keys, "auto must not mix auth key with jwt");
const ctxJwt = buildAuthorizationContext({ userJwt: "only-jwt" });
assert(ctxJwt.user_jwts?.[0] === "only-jwt", "jwt-only context");
assert(!ctxJwt.authorization_private_keys, "no empty auth keys");
const ctxApp = buildAuthorizationContext({ authorizationKey: "k", userJwt: "jwt", mode: "app" });
assert(ctxApp.authorization_private_keys?.[0] === "k", "app mode uses key");
assert(!ctxApp.user_jwts, "app mode ignores jwt");
const ctxUser = buildAuthorizationContext({ authorizationKey: "k", userJwt: "jwt", mode: "user" });
assert(ctxUser.user_jwts?.[0] === "jwt", "user mode uses jwt");
assert(!ctxUser.authorization_private_keys, "user mode ignores key");
const ctxEmpty = buildAuthorizationContext({});
assert(ctxEmpty === undefined, "empty context is undefined");

console.log("smoke-trading: ok");
