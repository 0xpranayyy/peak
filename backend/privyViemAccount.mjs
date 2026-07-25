/**
 * Viem account backed by Privy server wallet RPC (signMessage / signTypedData).
 * Requires wallet authorization key when Privy policies demand it (PEAK_PRIVY_AUTH_KEY).
 * Create at: Privy Dashboard → Wallets → Authorization keys → New key (private key once).
 */
import { createViemAccount } from "@privy-io/node/viem";
import { createWalletClient, http } from "viem";
import { polygon } from "viem/chains";

/**
 * @param {{
 *   privy: import('@privy-io/node').PrivyClient,
 *   walletId: string,
 *   address: `0x${string}`,
 *   rpcUrl?: string,
 *   authorizationKey?: string,
 * }} opts
 */
export function createPrivyWalletClient({ privy, walletId, address, rpcUrl, authorizationKey }) {
  const authorizationContext = authorizationKey
    ? { authorization_private_keys: [authorizationKey] }
    : undefined;

  // Official helper: wraps typed_data under params (Privy API requires params.typed_data).
  const account = createViemAccount(privy, {
    walletId,
    address,
    ...(authorizationContext ? { authorizationContext } : {}),
  });

  return createWalletClient({
    account,
    chain: polygon,
    transport: http(rpcUrl || undefined),
  });
}

function walletIdFromAccount(a) {
  return a?.id || a?.wallet_id || a?.walletId || a?.provider_id || null;
}

function isEmbeddedEthereum(a) {
  if (!a) return false;
  const type = String(a.type || "").toLowerCase();
  if (type && type !== "wallet" && type !== "smart_wallet") return false;
  const chain = String(a.chain_type || a.chainType || "").toLowerCase();
  if (chain && chain !== "ethereum") return false;
  // Only Privy-managed / imported wallets can be signed server-side.
  return (
    a.connector_type === "embedded" ||
    a.wallet_client === "privy" ||
    a.walletClientType === "privy" ||
    a.wallet_client_type === "privy" ||
    a.imported === true
  );
}

/**
 * Find a Privy-signable wallet whose address exactly matches `eoa`.
 * Does not fall back to a different Peak embedded wallet.
 * @param {import('@privy-io/node').PrivyClient} privy
 * @param {string} userId
 * @param {string} eoa
 */
export async function findSignableWalletForAddress(privy, userId, eoa) {
  if (!eoa) return null;
  const user = await privy.users()._get(userId);
  const target = String(eoa).toLowerCase();
  const accounts = user?.linked_accounts || [];

  for (const a of accounts) {
    if (String(a.address || "").toLowerCase() !== target) continue;
    if (!isEmbeddedEthereum(a) && a.imported !== true) continue;
    const id = walletIdFromAccount(a);
    if (id) return { walletId: id, address: a.address };
  }
  return null;
}

/**
 * Find Privy ethereum wallet id for a user (+ optional address match).
 * When `eoa` is set, prefers an exact match, then any embedded wallet.
 * @param {import('@privy-io/node').PrivyClient} privy
 * @param {string} userId
 * @param {string|null|undefined} eoa
 */
export async function findEmbeddedWalletId(privy, userId, eoa) {
  const exact = eoa ? await findSignableWalletForAddress(privy, userId, eoa) : null;
  if (exact) return exact;

  const user = await privy.users()._get(userId);
  const accounts = user?.linked_accounts || [];

  for (const a of accounts) {
    if (!isEmbeddedEthereum(a)) continue;
    const id = walletIdFromAccount(a);
    if (!id || !a.address) continue;
    return { walletId: id, address: a.address };
  }

  return null;
}

/**
 * Ensure the Privy user has a server-signable ethereum wallet.
 * WalletConnect-only users get a new Peak embedded wallet for "I'm new" trading.
 * Do not call this on the existing-PM path (use findSignableWalletForAddress instead).
 * @returns {Promise<{ walletId: string, address: string, created: boolean }>}
 */
export async function ensureEmbeddedWallet(privy, userId, preferredEoa = null) {
  const existing = await findEmbeddedWalletId(privy, userId, preferredEoa);
  if (existing?.walletId && existing?.address) {
    return { ...existing, created: false };
  }

  // Prefer any embedded already linked (ignore address mismatch — WC login vs Peak wallet).
  const anyEmbedded = await findEmbeddedWalletId(privy, userId, null);
  if (anyEmbedded?.walletId && anyEmbedded?.address) {
    return { ...anyEmbedded, created: false };
  }

  const created = await privy.wallets().create({
    chain_type: "ethereum",
    owner: { user_id: userId },
  });
  const walletId = created?.id;
  const address = created?.address;
  if (!walletId || !address) {
    throw new Error("Privy did not return a wallet id/address when creating an embedded wallet");
  }
  return { walletId, address, created: true };
}
