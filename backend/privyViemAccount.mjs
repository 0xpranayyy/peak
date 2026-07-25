/**
 * Viem account backed by Privy server wallet RPC (signMessage / signTypedData).
 * Requires wallet authorization key when Privy policies demand it (PEAK_PRIVY_AUTH_KEY).
 * Create at: Privy Dashboard → Wallets → Authorization keys → New key (private key once).
 */
import { createWalletClient, http } from "viem";
import { toAccount } from "viem/accounts";
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
  const auth = authorizationKey
    ? { authorization_context: { authorization_private_keys: [authorizationKey] } }
    : {};

  const account = toAccount({
    address,
    async signMessage({ message }) {
      const result = await privy.wallets().ethereum().signMessage(walletId, {
        message: typeof message === "string" ? message : message.raw,
        ...auth,
      });
      return result.signature;
    },
    async signTypedData(typedData) {
      const result = await privy.wallets().ethereum().signTypedData(walletId, {
        typed_data: typedData,
        ...auth,
      });
      return result.signature;
    },
    async signTransaction() {
      throw new Error("signTransaction via Privy is not used for Polymarket CLOB; use signTypedData.");
    },
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
 * Find Privy ethereum wallet id for a user (+ optional address match).
 * @param {import('@privy-io/node').PrivyClient} privy
 * @param {string} userId
 * @param {string|null|undefined} eoa
 */
export async function findEmbeddedWalletId(privy, userId, eoa) {
  const user = await privy.users()._get(userId);
  const target = eoa ? String(eoa).toLowerCase() : null;
  const accounts = user?.linked_accounts || [];

  // Exact address match only if that account is Privy-signable.
  if (target) {
    for (const a of accounts) {
      if (String(a.address || "").toLowerCase() !== target) continue;
      if (!isEmbeddedEthereum(a) && a.imported !== true) continue;
      const id = walletIdFromAccount(a);
      if (id) return { walletId: id, address: a.address };
    }
  }

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
