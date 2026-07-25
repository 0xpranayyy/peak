/**
 * Polymarket Deposit Wallet + per-user CLOB helpers.
 * Activates when Builder (+ optional Relayer) credentials are present.
 * Privy remote signing uses walletId from session when available.
 */
import { createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { polygon } from "viem/chains";
import { ClobClient, SignatureTypeV2 } from "@polymarket/clob-client-v2";

const HOST = "https://clob.polymarket.com";
const CHAIN_ID = 137;
const DEFAULT_RELAYER_URL = "https://relayer-v2.polymarket.com/";

/**
 * @param {{
 *   builderConfigured: boolean,
 *   relayerConfigured: boolean,
 *   builderKey?: string,
 *   builderSecret?: string,
 *   builderPassphrase?: string,
 *   polygonRpcUrl?: string,
 *   relayerUrl?: string,
 * }} cfg
 */
export function createTradingSetupContext(cfg) {
  return cfg;
}

/**
 * Build a RelayClient when packages + Builder creds are available.
 * Signer must be a viem WalletClient (EOA).
 */
export async function createRelayClient(walletClient, cfg) {
  if (!cfg.builderConfigured) {
    throw new Error("Builder credentials are not configured");
  }
  const { BuilderApiKeyCreds, BuilderConfig } = await import("@polymarket/builder-signing-sdk");
  const { RelayClient } = await import("@polymarket/builder-relayer-client");

  const builderCreds = {
    key: cfg.builderKey,
    secret: cfg.builderSecret,
    passphrase: cfg.builderPassphrase,
  };
  const builderConfig = new BuilderConfig({ localBuilderCreds: builderCreds });
  const relayerUrl = cfg.relayerUrl || DEFAULT_RELAYER_URL;
  return new RelayClient(relayerUrl, CHAIN_ID, walletClient, builderConfig);
}

/** @param {string} privateKeyHex @param {string|undefined} rpcUrl */
export function walletFromPrivateKey(privateKeyHex, rpcUrl) {
  const account = privateKeyToAccount(privateKeyHex);
  return createWalletClient({
    account,
    chain: polygon,
    transport: http(rpcUrl || undefined),
  });
}

/**
 * Deploy (or derive) a Deposit Wallet for a new-path user.
 * @returns {Promise<{ accountWallet: string, deployed: boolean, txHash?: string, status: string, message: string }>}
 */
export async function deployOrLinkDepositWallet({ walletClient, cfg, alreadyDeployedAddress }) {
  const relay = await createRelayClient(walletClient, cfg);
  const derived = await relay.deriveDepositWalletAddress();
  const accountWallet = alreadyDeployedAddress || derived;

  let isDeployed = false;
  try {
    isDeployed = Boolean(await relay.getDeployed(accountWallet, "WALLET"));
  } catch {
    isDeployed = false;
  }

  if (isDeployed || (alreadyDeployedAddress && alreadyDeployedAddress.toLowerCase() === derived.toLowerCase())) {
    return {
      accountWallet: derived,
      deployed: true,
      status: "deposit_ready",
      message: "Deposit wallet is ready.",
    };
  }

  const response = await relay.deployDepositWallet();
  const result = await response.wait();
  if (!result) {
    throw new Error("Deposit wallet deployment failed (no confirmation from relayer)");
  }

  return {
    accountWallet: derived,
    deployed: true,
    txHash: result.transactionHash,
    status: "deposit_deployed",
    message: "Deposit wallet deployed.",
  };
}

/**
 * Create a per-user CLOB client (EOA signer + funder = account wallet).
 * @param {{ walletClient: any, funderAddress: string, signatureType: number, rpcUrl?: string }} opts
 */
export async function createUserClobClient({ walletClient, funderAddress, signatureType }) {
  const signer = walletClient;
  const temp = new ClobClient({ host: HOST, chain: CHAIN_ID, signer });
  const creds = await temp.createOrDeriveApiKey();

  let sigType = SignatureTypeV2.EOA;
  if (signatureType === 1) sigType = SignatureTypeV2.POLY_PROXY;
  else if (signatureType === 2) sigType = SignatureTypeV2.POLY_GNOSIS_SAFE;
  else if (signatureType === 3) sigType = SignatureTypeV2.POLY_1271;

  return new ClobClient({
    host: HOST,
    chain: CHAIN_ID,
    signer,
    creds,
    signatureType: sigType,
    funderAddress,
  });
}

/**
 * Map wallet type name → CLOB signature type int.
 * @param {string|null|undefined} name
 * @param {number|null|undefined} fallback
 */
export function signatureTypeFromWalletName(name, fallback = 3) {
  const n = String(name || "").toUpperCase();
  if (n.includes("PROXY")) return 1;
  if (n.includes("SAFE") || n.includes("GNOSIS")) return 2;
  if (n.includes("DEPOSIT") || n.includes("1271") || n.includes("POLY_1271")) return 3;
  if (n.includes("EOA")) return 0;
  return fallback ?? 3;
}
