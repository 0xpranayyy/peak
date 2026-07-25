/**
 * Map raw CLOB / Privy / proxy errors to actionable copy for the iOS client.
 * Never return raw typed_data / JSON blobs.
 */

/**
 * @param {unknown} raw
 * @param {{ balanceUSD?: number|null, code?: string|null }} [opts]
 * @returns {{ error: string, code: string, status: number }}
 */
export function mapOrderError(raw, { balanceUSD = null, code: hintCode = null } = {}) {
  const text = String(raw || "").trim();
  const lower = text.toLowerCase();
  const hint = String(hintCode || "").toLowerCase();

  if (
    hint === "import_wallet_required" ||
    lower.includes("import_wallet_required") ||
    lower.includes("import the private key") ||
    lower.includes("import your wallet")
  ) {
    return {
      error: "Import the private key or seed for this Polymarket wallet to enable trading.",
      code: "import_wallet_required",
      status: 400,
    };
  }

  // Privy wallet RPC: user-owned / imported wallets need a valid user JWT (or matching auth key).
  if (
    hint === "wallet_auth_failed" ||
    lower.includes("no valid authorization") ||
    lower.includes("user signing keys") ||
    lower.includes("authorization keys") ||
    lower.includes("no_valid_user_session_keys") ||
    lower.includes("zero_correct_authorization_signatures")
  ) {
    return {
      error:
        "Couldn’t authorize this wallet to trade. Try importing again or contact support.",
      code: "wallet_auth_failed",
      status: 401,
    };
  }

  if (
    hint === "sign_failed" ||
    (lower.includes("params") && (lower.includes("required") || lower.includes("typed_data"))) ||
    lower.includes("typed_data") ||
    lower.includes("unrecognized_keys") ||
    lower.includes("invalid_data") ||
    (lower.includes("privy") && (lower.includes("sign") || lower.includes("400")))
  ) {
    return {
      error: "Couldn’t sign this order. Try again.",
      code: "sign_failed",
      status: 502,
    };
  }

  if (
    lower.includes("not enough balance") ||
    lower.includes("insufficient") ||
    lower.includes("balance / allowance") ||
    lower.includes("allowance")
  ) {
    const balNote =
      balanceUSD != null && Number.isFinite(balanceUSD)
        ? ` Available cash: $${balanceUSD.toFixed(2)}.`
        : "";
    return {
      error: `Insufficient funds or allowance.${balNote} Deposit USDC / pUSD to your trading wallet, then try again.`,
      code: "insufficient_funds",
      status: 400,
    };
  }
  if (lower.includes("no match") || lower.includes("couldn't be fully filled") || lower.includes("fok")) {
    return {
      error: "No fill at this price (liquidity too thin). Try a limit order or a smaller size.",
      code: "no_fill",
      status: 400,
    };
  }
  if (lower.includes("closed") || lower.includes("not accepting") || lower.includes("inactive")) {
    return {
      error: "This market is closed or not accepting orders.",
      code: "market_closed",
      status: 400,
    };
  }
  if (lower.includes("builder")) {
    return {
      error: "Trading isn’t ready yet — Builder credentials are missing on the Peak backend.",
      code: "builder_not_ready",
      status: 503,
    };
  }
  if (lower.includes("tick") || lower.includes("invalid price") || lower.includes("min size")) {
    return {
      error: "Invalid price or size for this market. Adjust the amount or limit price.",
      code: "invalid_order",
      status: 400,
    };
  }
  if (lower.includes("approvals") || hint === "approvals_failed") {
    return {
      error: "Trading approvals aren’t ready yet. Open Account → Set up trading, then try again.",
      code: "approvals_failed",
      status: 400,
    };
  }

  // Never dump raw JSON / infra blobs to the client.
  if (
    (text.startsWith("{") && text.includes('"')) ||
    lower.includes("stack") ||
    lower.includes("axioserror")
  ) {
    return {
      error: "Couldn’t place order. Try again.",
      code: "order_failed",
      status: 400,
    };
  }

  return {
    error: text || "Order failed",
    code: "order_failed",
    status: 400,
  };
}

/** @param {unknown} err */
export function isImportWalletError(err) {
  if (!err) return false;
  if (err.code === "import_wallet_required") return true;
  const msg = String(err.safeMessage || err.message || err || "").toLowerCase();
  return (
    msg.includes("import_wallet_required") ||
    msg.includes("import the private key") ||
    msg.includes("import your wallet")
  );
}

/** Friendly cash sync failure copy + machine code for iOS CTAs. */
export function mapCashError(err) {
  if (isImportWalletError(err)) {
    return {
      cashError: "Import the private key or seed for this Polymarket wallet to enable trading.",
      cashErrorCode: "import_wallet_required",
      needsImport: true,
    };
  }
  const msg = String(err?.message || err || "").toLowerCase();
  if (
    msg.includes("no valid authorization") ||
    msg.includes("user signing keys") ||
    msg.includes("authorization keys") ||
    err?.code === "wallet_auth_failed"
  ) {
    return {
      cashError:
        "Couldn’t authorize this wallet to trade. Try importing again or contact support.",
      cashErrorCode: "wallet_auth_failed",
      needsImport: false,
    };
  }
  if (msg.includes("typed_data") || msg.includes("params") || msg.includes("unrecognized_keys")) {
    return {
      cashError: "Couldn’t sync cash balance. Try again in a moment.",
      cashErrorCode: "sign_failed",
      needsImport: false,
    };
  }
  if (typeof err?.safeMessage === "string" && err.safeMessage.trim()) {
    const mapped = mapOrderError(err.safeMessage, { code: err.code });
    return {
      cashError: mapped.error,
      cashErrorCode: mapped.code,
      needsImport: mapped.code === "import_wallet_required",
    };
  }
  return {
    cashError: "Couldn’t sync cash balance. Try again in a moment.",
    cashErrorCode: "cash_sync_failed",
    needsImport: false,
  };
}
