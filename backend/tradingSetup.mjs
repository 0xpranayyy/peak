/**
 * Polymarket Deposit Wallet + per-user CLOB helpers.
 * Activates when Builder (+ optional Relayer) credentials are present.
 * Privy remote signing uses walletId from session when available.
 */
import { createPublicClient, createWalletClient, encodeFunctionData, http, maxUint256 } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { polygon } from "viem/chains";
import { ClobClient, SignatureTypeV2 } from "@polymarket/clob-client-v2";

const HOST = "https://clob.polymarket.com";
const CHAIN_ID = 137;
const DEFAULT_RELAYER_URL = "https://relayer-v2.polymarket.com/";

/** Polygon V2 trading contracts (docs.polymarket.com/trading/deposit-wallets). */
const PUSD = "0xC011a7E12a19f7B1f670d46F03B03f3342E82DFB";
const CONDITIONAL_TOKENS = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045";
const CTF_EXCHANGE = "0xE111180000d2663C0091e4f400237545B87B996B";
const NEG_RISK_EXCHANGE = "0xe2222d279d744050d28e00520010520000310F59";

const erc20Abi = [
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
];

const erc1155Abi = [
  {
    type: "function",
    name: "setApprovalForAll",
    stateMutability: "nonpayable",
    inputs: [
      { name: "operator", type: "address" },
      { name: "approved", type: "bool" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "isApprovedForAll",
    stateMutability: "view",
    inputs: [
      { name: "account", type: "address" },
      { name: "operator", type: "address" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
];

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

/**
 * Gasless ERC-20 / ERC-1155 trading approvals for a Deposit Wallet via Relayer.
 * Checks on-chain allowances and submits only missing approvals.
 * @returns {Promise<{ skipped: boolean, txHash?: string, message: string, approvalsSet: number }>}
 */
export async function setupDepositWalletTradingApprovals({
  walletClient,
  cfg,
  depositWalletAddress,
  rpcUrl,
}) {
  if (!depositWalletAddress) {
    throw new Error("Deposit wallet address required for trading approvals");
  }

  const publicClient = createPublicClient({
    chain: polygon,
    transport: http(rpcUrl || cfg.polygonRpcUrl || undefined),
  });

  const wallet = /** @type {`0x${string}`} */ (depositWalletAddress);
  const exchanges = [CTF_EXCHANGE, NEG_RISK_EXCHANGE];
  /** @type {{ target: string, value: string, data: `0x${string}` }[]} */
  const calls = [];

  for (const exchange of exchanges) {
    const spender = /** @type {`0x${string}`} */ (exchange);
    let allowance = 0n;
    try {
      allowance = await publicClient.readContract({
        address: PUSD,
        abi: erc20Abi,
        functionName: "allowance",
        args: [wallet, spender],
      });
    } catch {
      allowance = 0n;
    }
    if (allowance < maxUint256 / 2n) {
      calls.push({
        target: PUSD,
        value: "0",
        data: encodeFunctionData({
          abi: erc20Abi,
          functionName: "approve",
          args: [spender, maxUint256],
        }),
      });
    }

    let approved = false;
    try {
      approved = await publicClient.readContract({
        address: CONDITIONAL_TOKENS,
        abi: erc1155Abi,
        functionName: "isApprovedForAll",
        args: [wallet, spender],
      });
    } catch {
      approved = false;
    }
    if (!approved) {
      calls.push({
        target: CONDITIONAL_TOKENS,
        value: "0",
        data: encodeFunctionData({
          abi: erc1155Abi,
          functionName: "setApprovalForAll",
          args: [spender, true],
        }),
      });
    }
  }

  if (calls.length === 0) {
    return {
      skipped: true,
      approvalsSet: 0,
      message: "Trading approvals already set.",
    };
  }

  const relay = await createRelayClient(walletClient, cfg);
  const deadline = String(Math.floor(Date.now() / 1000) + 240);
  const response = await relay.executeDepositWalletBatch(calls, depositWalletAddress, deadline);
  const result = await response.wait();
  if (!result) {
    const err = new Error("Trading approvals failed (no confirmation from relayer)");
    err.code = "approvals_failed";
    err.safeMessage =
      "Couldn’t finish trading approvals. Try Set up trading again, or deposit and retry.";
    throw err;
  }

  return {
    skipped: false,
    approvalsSet: calls.length,
    txHash: result.transactionHash,
    message: "Trading approvals confirmed.",
  };
}
