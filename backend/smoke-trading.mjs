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

console.log("smoke-trading: ok");
