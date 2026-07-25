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

/**
 * Find Privy embedded ethereum wallet id for a user + address.
 * @param {import('@privy-io/node').PrivyClient} privy
 * @param {string} userId
 * @param {string} eoa
 */
export async function findEmbeddedWalletId(privy, userId, eoa) {
  const user = await privy.users()._get(userId);
  const target = eoa.toLowerCase();
  const accounts = user?.linked_accounts || [];
  for (const a of accounts) {
    if (a?.type !== "wallet" && a?.type !== "smart_wallet") continue;
    if (String(a.address || "").toLowerCase() !== target) continue;
    if (a.id) return a.id;
  }
  for (const a of accounts) {
    if (a?.connector_type === "embedded" && a?.chain_type === "ethereum" && a.id) {
      if (!eoa || String(a.address || "").toLowerCase() === target) return a.id;
    }
  }
  return null;
}
