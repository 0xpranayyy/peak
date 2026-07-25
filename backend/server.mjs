// Peak trading API — legacy one-wallet proxy + Privy per-user sessions.
// Builder credentials unlock Deposit Wallet deploy / CLOB for Privy users.
import "dotenv/config";
import crypto from "crypto";
import express from "express";
import cors from "cors";
import rateLimit from "express-rate-limit";
import { PrivyClient } from "@privy-io/node";
import { ClobClient, Side, OrderType, SignatureTypeV2, AssetType } from "@polymarket/clob-client-v2";
import { createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { resolvePolymarketAccount } from "./polymarketAccount.mjs";
import { loadSessions, getSession, setSession, sessions, sessionStorePath } from "./sessionStore.mjs";
import {
  deployOrLinkDepositWallet,
  createUserClobClient,
  signatureTypeFromWalletName,
  setupDepositWalletTradingApprovals,
} from "./tradingSetup.mjs";
import {
  createPrivyWalletClient,
  findEmbeddedWalletId,
  findSignableWalletForAddress,
  ensureEmbeddedWallet,
} from "./privyViemAccount.mjs";
import { mapOrderError, isImportWalletError, mapCashError } from "./orderErrors.mjs";
import { mountLegalPages } from "./legalPages.mjs";

const {
  PORT = 8080,
  APP_TOKEN,
  PRIVATE_KEY,
  FUNDER_ADDRESS,
  SIGNATURE_TYPE = "3",
  CLOB_API_KEY,
  CLOB_API_SECRET,
  CLOB_API_PASSPHRASE,
  POLY_BUILDER_CODE,
  POLYMARKET_BUILDER_API_KEY,
  POLYMARKET_BUILDER_SECRET,
  POLYMARKET_BUILDER_PASSPHRASE,
  PRIVY_APP_ID,
  PRIVY_APP_SECRET,
  POLYGON_RPC_URL,
  RELAYER_API_KEY,
  RELAYER_API_KEY_ADDRESS,
  POLYMARKET_RELAYER_URL,
  PEAK_PRIVY_AUTH_KEY,
  CORS_ORIGINS = "",
  TRUST_PROXY = "",
  RATE_LIMIT_WINDOW_MS = "60000",
  RATE_LIMIT_MAX = "120",
} = process.env;

const HOST = "https://clob.polymarket.com";
const DATA = "https://data-api.polymarket.com";
const BRIDGE = "https://bridge.polymarket.com";
const CHAIN_ID = 137;

const legacyEnabled = Boolean(APP_TOKEN && PRIVATE_KEY && FUNDER_ADDRESS);
const privyEnabled = Boolean(PRIVY_APP_ID && PRIVY_APP_SECRET);
const builderConfigured = Boolean(
  POLYMARKET_BUILDER_API_KEY && POLYMARKET_BUILDER_SECRET && POLYMARKET_BUILDER_PASSPHRASE
);
const relayerConfigured = Boolean(RELAYER_API_KEY && RELAYER_API_KEY_ADDRESS);

if (!legacyEnabled && !privyEnabled) {
  console.error("Configure either legacy APP_TOKEN/PRIVATE_KEY/FUNDER_ADDRESS or PRIVY_APP_ID/PRIVY_APP_SECRET");
  process.exit(1);
}

const privy = privyEnabled
  ? new PrivyClient({ appId: PRIVY_APP_ID, appSecret: PRIVY_APP_SECRET })
  : null;

const tradingCfg = {
  builderConfigured,
  relayerConfigured,
  builderKey: POLYMARKET_BUILDER_API_KEY,
  builderSecret: POLYMARKET_BUILDER_SECRET,
  builderPassphrase: POLYMARKET_BUILDER_PASSPHRASE,
  polygonRpcUrl: POLYGON_RPC_URL,
  relayerUrl: POLYMARKET_RELAYER_URL,
};

loadSessions();

let legacyClient;

async function initLegacyClient() {
  if (!legacyEnabled) return;
  const account = privateKeyToAccount(PRIVATE_KEY);
  const signer = createWalletClient({
    account,
    transport: http(POLYGON_RPC_URL || undefined),
  });

  let creds =
    CLOB_API_KEY && CLOB_API_SECRET && CLOB_API_PASSPHRASE
      ? { key: CLOB_API_KEY, secret: CLOB_API_SECRET, passphrase: CLOB_API_PASSPHRASE }
      : undefined;

  if (!creds) {
    const temp = new ClobClient({ host: HOST, chain: CHAIN_ID, signer });
    creds = await temp.createOrDeriveApiKey();
    console.log("Derived CLOB API key (credential redacted from logs)");
  }

  const signatureType =
    Number(SIGNATURE_TYPE) === 3 ? SignatureTypeV2.POLY_1271 : Number(SIGNATURE_TYPE);

  legacyClient = new ClobClient({
    host: HOST,
    chain: CHAIN_ID,
    signer,
    creds,
    signatureType,
    funderAddress: FUNDER_ADDRESS,
  });

  console.log("Legacy CLOB ready. Funder:", FUNDER_ADDRESS, "Signer:", account.address);
}

const app = express();
if (/^(1|true|yes)$/i.test(String(TRUST_PROXY))) {
  app.set("trust proxy", 1);
}

app.use(express.json({ limit: "64kb" }));

// CORS: off when CORS_ORIGINS is empty (mobile-safe default). When set, allow-list only.
// Native apps / curl send no Origin — those stay allowed. Never honor "*".
function parseCorsOrigins(raw) {
  const parsed = String(raw || "")
    .split(",")
    .map((s) => s.trim().replace(/\/$/, ""))
    .filter(Boolean)
    .filter((o) => o !== "*");
  // Keep https://… and local http://localhost|127.0.0.1 only (secure default when set).
  return parsed.filter((o) => {
    try {
      const u = new URL(o);
      const local = u.hostname === "localhost" || u.hostname === "127.0.0.1";
      if (u.protocol === "https:") return true;
      if (u.protocol === "http:" && local) return true;
      console.warn(`CORS_ORIGINS: dropping insecure/non-https origin: ${o}`);
      return false;
    } catch {
      console.warn(`CORS_ORIGINS: invalid origin skipped: ${o}`);
      return false;
    }
  });
}
const corsOrigins = parseCorsOrigins(CORS_ORIGINS);
app.use(
  cors({
    origin: corsOrigins.length
      ? (origin, cb) => {
          // No Origin = native app / server-to-server — not a browser CORS threat.
          if (!origin) return cb(null, true);
          if (corsOrigins.includes(origin.replace(/\/$/, ""))) return cb(null, true);
          return cb(new Error("CORS origin not allowed"));
        }
      : false,
    credentials: Boolean(corsOrigins.length),
    methods: ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowedHeaders: ["Authorization", "Content-Type", "X-Peak-Auth"],
  })
);

const windowMs = Math.max(1000, Number(RATE_LIMIT_WINDOW_MS) || 60_000);
const maxReqs = Math.max(10, Number(RATE_LIMIT_MAX) || 120);
app.use(
  rateLimit({
    windowMs,
    max: maxReqs,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: "Too many requests" },
    skip: (req) => req.path === "/health" || req.path === "/health/live",
  })
);

// Request logging — method/path/status/duration only (never Authorization or bodies)
app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    console.log(`${req.method} ${req.path} ${res.statusCode} ${Date.now() - start}ms`);
  });
  next();
});

function timingSafeEqualStrings(a, b) {
  const bufA = Buffer.from(String(a ?? ""));
  const bufB = Buffer.from(String(b ?? ""));
  if (bufA.length !== bufB.length) {
    // Still run a compare of equal-length buffers so failure timing doesn't
    // depend on the length mismatch itself.
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

const wrap = (fn) => (req, res) =>
  fn(req, res).catch((e) => {
    // Log full detail server-side only — never echo raw internal error text
    // (which can include upstream SDK/URL/path detail) back to the client.
    console.error(e?.message ?? e);
    const status = Number(e?.httpStatus || e?.status) || 500;
    const code = e?.code || (status >= 500 ? "internal_error" : "request_failed");
    const publicFields =
      e?.publicFields && typeof e.publicFields === "object" ? e.publicFields : {};
    // Prefer explicit safe client copy; never leak upstream URLs/stacks on 5xx.
    const error =
      typeof e?.safeMessage === "string" && e.safeMessage.trim()
        ? e.safeMessage.trim()
        : status >= 500
          ? "Internal error. Try again."
          : String(e?.message ?? "Request failed");
    res.status(status).json({ error, code, ...publicFields });
  });

/** Auth opts for Privy wallet RPC (user-owned wallets need the access token). */
function privySignOpts(req) {
  return {
    userJwt: req?.auth?.mode === "privy" ? req.auth.accessToken : undefined,
  };
}

/** Resolve a Privy-backed viem wallet client for the session. */
async function walletClientForSession(session, { userJwt } = {}) {
  if (!privy) {
    const err = new Error("Privy is not configured");
    err.code = "setup_failed";
    err.httpStatus = 503;
    err.safeMessage = "Trading isn’t ready yet. Try again in a moment.";
    throw err;
  }

  let walletId = session.walletId;
  let signingAddress = session.eoa;
  const isExisting = session.path === "existing";

  if (isExisting) {
    // Prefer the walletId stored at import time — linked_accounts can lag briefly.
    if (session.imported && session.walletId && session.eoa) {
      walletId = session.walletId;
      signingAddress = session.eoa;
    } else {
      // Existing PM path: resolve a Privy-signable wallet that matches the linked signer.
      // Never auto-create a different embedded wallet here.
      try {
        const found = await findSignableWalletForAddress(privy, session.userId, session.eoa);
        if (!found?.walletId || !found?.address) {
          const err = new Error("import_wallet_required");
          err.code = "import_wallet_required";
          err.httpStatus = 400;
          err.safeMessage =
            "Import the private key or seed for this Polymarket wallet to enable trading.";
          err.publicFields = {
            needsDeploy: false,
            syncReady: Boolean(session.accountWallet),
            builderConfigured,
            relayerConfigured,
          };
          throw err;
        }
        walletId = found.walletId;
        signingAddress = found.address;
        if (
          session.walletId !== walletId ||
          String(session.eoa || "").toLowerCase() !== String(signingAddress).toLowerCase()
        ) {
          const patch = { ...session, walletId, eoa: signingAddress, clobClient: null };
          setSession(session.userId, patch);
          Object.assign(session, patch);
        }
      } catch (e) {
        if (e?.code === "import_wallet_required") throw e;
        console.error("findSignableWalletForAddress failed:", e?.message ?? e);
        const err = new Error(e?.message ?? "Could not resolve trading wallet");
        err.code = "import_wallet_required";
        err.httpStatus = 400;
        err.safeMessage =
          "Import the private key or seed for this Polymarket wallet to enable trading.";
        err.publicFields = {
          needsDeploy: false,
          syncReady: Boolean(session.accountWallet),
          builderConfigured,
          relayerConfigured,
        };
        throw err;
      }
    }
  } else if (!walletId) {
    try {
      const ensured = await ensureEmbeddedWallet(privy, session.userId, session.eoa);
      walletId = ensured.walletId;
      signingAddress = ensured.address;
      const patch = {
        ...session,
        walletId,
        eoa: signingAddress,
      };
      // Keep the login wallet if it differed (WalletConnect / external).
      if (
        session.eoa &&
        String(session.eoa).toLowerCase() !== String(signingAddress).toLowerCase()
      ) {
        patch.loginEoa = session.eoa;
      }
      setSession(session.userId, patch);
      Object.assign(session, patch);
    } catch (e) {
      console.error("ensureEmbeddedWallet failed:", e?.message ?? e);
      const err = new Error(e?.message ?? "Could not create Peak trading wallet");
      err.code = "embedded_wallet_required";
      err.httpStatus = 501;
      err.safeMessage =
        "Couldn’t create a Peak trading wallet for this account. Sign in with email or Apple, then try again.";
      err.publicFields = {
        needsDeploy: true,
        syncReady: false,
        builderConfigured,
        relayerConfigured,
      };
      throw err;
    }
  }

  if (!walletId || !signingAddress) {
    if (isExisting) {
      const err = new Error("import_wallet_required");
      err.code = "import_wallet_required";
      err.httpStatus = 400;
      err.safeMessage =
        "Import the private key or seed for this Polymarket wallet to enable trading.";
      err.publicFields = {
        needsDeploy: false,
        syncReady: Boolean(session.accountWallet),
        builderConfigured,
        relayerConfigured,
      };
      throw err;
    }
    const err = new Error("No Privy embedded wallet id for this user");
    err.code = "embedded_wallet_required";
    err.httpStatus = 501;
    err.safeMessage =
      "Peak needs a trading wallet to continue. Sign in with email or Apple, or choose “I already trade elsewhere”.";
    err.publicFields = {
      needsDeploy: true,
      syncReady: false,
      builderConfigured,
      relayerConfigured,
    };
    throw err;
  }

  // Imported / user-owned → JWT only. Peak embedded (new path) may use JWT or auth key.
  const authMode = session.imported || session.path === "existing" ? "user" : "auto";
  return createPrivyWalletClient({
    privy,
    walletId,
    address: signingAddress,
    rpcUrl: POLYGON_RPC_URL,
    authorizationKey: PEAK_PRIVY_AUTH_KEY,
    userJwt,
    authMode,
  });
}

async function ensureUserClob(session, { userJwt } = {}) {
  // Rebuild when the access token changes — Privy user signing keys are JWT-bound.
  if (session.clobClient && session._privyAuthJwt && session._privyAuthJwt === userJwt) {
    return session.clobClient;
  }
  const funder = session.accountWallet || session.eoa;
  const walletClient = await walletClientForSession(session, { userJwt });
  const sigType = session.walletType ?? signatureTypeFromWalletName(session.walletTypeName, 3);
  try {
    const client = await createUserClobClient({
      walletClient,
      funderAddress: funder,
      signatureType: sigType,
    });
    setSession(session.userId, {
      ...session,
      clobClient: client,
      _privyAuthJwt: userJwt || null,
      ready: true,
    });
    return client;
  } catch (e) {
    const mapped = mapOrderError(extractClobError(e), { code: e?.code });
    if (mapped.code === "wallet_auth_failed") {
      const err = new Error(mapped.error);
      err.code = mapped.code;
      err.httpStatus = mapped.status;
      err.safeMessage = mapped.error;
      throw err;
    }
    throw e;
  }
}

/** Pull a readable string from CLOB / Axios / ApiError shapes. */
function extractClobError(err) {
  if (!err) return "Order failed";
  const data = err.data ?? err.response?.data;
  if (typeof data === "string" && data.trim()) return data.trim();
  if (data && typeof data === "object") {
    const nested =
      data.errorMsg ||
      data.error ||
      data.message ||
      (typeof data.error_message === "string" ? data.error_message : data.error_message?.error);
    if (nested) return String(nested);
  }
  if (err.errorMsg) return String(err.errorMsg);
  if (err.message) return String(err.message);
  return String(err);
}

/** CLOB collateral balance is typically 6-decimal micro-units when very large. */
function normalizeCollateralUSD(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return null;
  return n > 100_000 ? n / 1_000_000 : n;
}

function normalizeShareBalance(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return null;
  // Conditional token balances are often 6-decimal fixed-point.
  return n > 1_000_000 ? n / 1_000_000 : n;
}

async function fetchCollateralBalance(client, signatureType = null) {
  try {
    const params = { asset_type: AssetType.COLLATERAL };
    if (signatureType != null && Number.isFinite(Number(signatureType))) {
      params.signature_type = Number(signatureType);
    }
    await client.updateBalanceAllowance?.(params).catch(() => {});
    const bal = await client.getBalanceAllowance(params);
    return {
      raw: bal,
      usd: normalizeCollateralUSD(bal?.balance),
    };
  } catch (e) {
    return { raw: null, usd: null, error: e };
  }
}

async function fetchConditionalBalance(client, tokenID, signatureType = null) {
  try {
    const params = { asset_type: AssetType.CONDITIONAL, token_id: tokenID };
    if (signatureType != null && Number.isFinite(Number(signatureType))) {
      params.signature_type = Number(signatureType);
    }
    await client.updateBalanceAllowance?.(params).catch(() => {});
    const bal = await client.getBalanceAllowance(params);
    return {
      raw: bal,
      shares: normalizeShareBalance(bal?.balance),
    };
  } catch (e) {
    return { raw: null, shares: null, error: e };
  }
}

/**
 * Place a CLOB order. FOK/FAK → market order (amount); GTC/GTD → limit (price+size).
 */
async function placeClobOrder(client, body) {
  const {
    tokenID,
    price,
    size,
    amount,
    side,
    orderType = "FOK",
    tickSize,
    negRisk,
  } = body;

  const sideEnum = String(side).toUpperCase() === "SELL" ? Side.SELL : Side.BUY;
  const typeKey = String(orderType || "FOK").toUpperCase();
  const isMarket = typeKey === "FOK" || typeKey === "FAK";

  const [resolvedTick, resolvedNegRisk] = await Promise.all([
    tickSize ?? client.getTickSize(tokenID),
    negRisk ?? client.getNegRisk(tokenID),
  ]);
  const opts = { tickSize: String(resolvedTick), negRisk: Boolean(resolvedNegRisk) };
  const builder = POLY_BUILDER_CODE ? { builderCode: POLY_BUILDER_CODE } : {};

  let result;
  if (isMarket) {
    const marketAmount =
      amount != null && Number(amount) > 0
        ? Number(amount)
        : sideEnum === Side.BUY
          ? Number(size) * Number(price)
          : Number(size);
    if (!(marketAmount > 0)) {
      const err = new Error("Invalid order amount");
      err.code = "invalid_order";
      throw err;
    }
    result = await client.createAndPostMarketOrder(
      {
        tokenID,
        amount: marketAmount,
        side: sideEnum,
        price: price != null ? Number(price) : undefined,
        orderType: OrderType[typeKey] ?? OrderType.FOK,
        ...builder,
      },
      opts,
      OrderType[typeKey] ?? OrderType.FOK
    );
  } else {
    result = await client.createAndPostOrder(
      {
        tokenID,
        price: Number(price),
        size: Number(size),
        side: sideEnum,
        ...builder,
      },
      opts,
      OrderType[typeKey] ?? OrderType.GTC
    );
  }

  if (result && result.success === false) {
    const mapped = mapOrderError(result.errorMsg || result.error || result.status || "Order rejected");
    const err = new Error(mapped.error);
    err.code = mapped.code;
    err.httpStatus = mapped.status;
    err.clob = result;
    throw err;
  }

  return result;
}

const getJSON = async (url, opts) => {
  const r = await fetch(url, opts);
  if (!r.ok) throw new Error(`${url} → ${r.status}: ${await r.text()}`);
  return r.json();
};

async function authenticate(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) {
    return res.status(401).json({ error: "unauthorized" });
  }

  // Legacy static token (constant-time compare — avoids leaking a timing side-channel)
  if (legacyEnabled && timingSafeEqualStrings(token, APP_TOKEN)) {
    req.auth = { mode: "legacy" };
    return next();
  }

  // Privy access token
  if (privy) {
    try {
      const claims = await privy.utils().auth().verifyAccessToken(token);
      req.auth = {
        mode: "privy",
        userId: claims.user_id || claims.userId,
        sessionId: claims.session_id || claims.sessionId,
        // Needed for Privy wallet RPC on user-owned / imported wallets.
        accessToken: token,
      };
      return next();
    } catch (e) {
      console.warn("Privy verify failed:", e?.message ?? e);
    }
  }

  return res.status(401).json({ error: "unauthorized" });
}

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    legacy: legacyEnabled,
    privy: privyEnabled,
    privyAuthKey: Boolean(PEAK_PRIVY_AUTH_KEY),
    builder: builderConfigured,
    relayer: relayerConfigured,
    funder: legacyEnabled ? FUNDER_ADDRESS : null,
    sessions: sessions.size,
    sessionStore: sessionStorePath,
    cors: corsOrigins.length ? "allowlist" : "off",
    uptimeSec: Math.floor(process.uptime()),
  });
});

app.get("/health/live", (_req, res) => {
  res.json({ ok: true });
});

// Public legal / support pages (App Store URLs → same HTTPS API host after deploy).
mountLegalPages(app);

// Public enough for health + legal; everything else needs auth.
app.use(authenticate);

app.post("/auth/session", wrap(async (req, res) => {
  if (req.auth.mode !== "privy") {
    return res.status(400).json({ error: "Privy session required" });
  }
  const eoa = String(req.body?.eoa || "").trim();
  if (!/^0x[a-fA-F0-9]{40}$/.test(eoa)) {
    return res.status(400).json({ error: "Valid eoa address required" });
  }

  const pathRaw = String(req.body?.path || "").toLowerCase();
  const path = pathRaw === "existing" || pathRaw === "new" ? pathRaw : null;
  const accountWalletHint = String(req.body?.accountWallet || "").trim() || null;

  const existing = getSession(req.auth.userId);
  const resolvedPath = path || existing?.path || "new";

  let walletId = existing?.walletId || null;
  let eoaForSession = eoa;
  let loginEoa = existing?.loginEoa || null;
  if (privy && resolvedPath === "new") {
    try {
      const ensured = await ensureEmbeddedWallet(privy, req.auth.userId, eoa);
      walletId = ensured.walletId;
      if (String(ensured.address).toLowerCase() !== eoa.toLowerCase()) {
        loginEoa = eoa;
        eoaForSession = ensured.address;
      } else {
        eoaForSession = ensured.address;
      }
    } catch (e) {
      console.warn("auth/session ensureEmbeddedWallet:", e?.message ?? e);
    }
  } else if (privy && resolvedPath === "existing") {
    // Exact match only — never attach a mismatched Peak embedded wallet.
    try {
      const found = await findSignableWalletForAddress(privy, req.auth.userId, eoa);
      if (found?.walletId) {
        walletId = found.walletId;
        if (found.address) eoaForSession = found.address;
      } else {
        walletId = null;
      }
    } catch (e) {
      console.warn("auth/session findSignableWalletForAddress:", e?.message ?? e);
      walletId = null;
    }
  } else if (privy && !walletId) {
    try {
      const found = await findEmbeddedWalletId(privy, req.auth.userId, eoa);
      if (found?.walletId) {
        walletId = found.walletId;
        if (found.address) eoaForSession = found.address;
      }
    } catch (e) {
      console.warn("auth/session findEmbeddedWalletId:", e?.message ?? e);
    }
  }

  const resolved = await resolvePolymarketAccount({
    signer: eoaForSession,
    path: resolvedPath,
    accountWalletHint: accountWalletHint || existing?.accountWallet || null,
  });

  const session = {
    userId: req.auth.userId,
    eoa: eoaForSession,
    loginEoa,
    walletId,
    accountWallet: resolved.accountWallet,
    safeAddress: resolved.accountWallet,
    walletType: resolved.walletType,
    walletTypeName: resolved.walletTypeName,
    path: resolvedPath,
    ready: Boolean(resolved.syncReady && (!resolved.needsDeploy || builderConfigured)),
    needsDeploy: Boolean(resolved.needsDeploy),
  };
  setSession(req.auth.userId, session);

  res.json({
    ...session,
    signer: eoaForSession,
    syncReady: resolved.syncReady,
    builderConfigured,
    relayerConfigured,
    profile: resolved.profile,
    message: resolved.message,
    next:
      resolved.needsDeploy && !builderConfigured
        ? "Configure Builder credentials, then call POST /trading/setup"
        : resolved.needsDeploy
          ? "Call POST /trading/setup to deploy the deposit wallet"
          : resolved.syncReady
            ? "Portfolio linked to account wallet"
            : "Select account type or import a Polymarket wallet",
  });
}));

/**
 * Re-resolve account wallet / type without changing path.
 */
app.post("/trading/resolve", wrap(async (req, res) => {
  if (req.auth.mode !== "privy") {
    return res.status(400).json({ error: "Privy session required" });
  }
  const session = getSession(req.auth.userId);
  const eoa = String(req.body?.eoa || session?.eoa || "").trim();
  if (!/^0x[a-fA-F0-9]{40}$/.test(eoa)) {
    return res.status(400).json({ error: "Call POST /auth/session with eoa first" });
  }
  const path = session?.path || (String(req.body?.path || "new").toLowerCase() === "existing" ? "existing" : "new");
  const hint = String(req.body?.accountWallet || session?.accountWallet || "").trim() || null;

  const resolved = await resolvePolymarketAccount({
    signer: eoa,
    path,
    accountWalletHint: hint,
  });

  const next = {
    userId: req.auth.userId,
    eoa,
    accountWallet: resolved.accountWallet,
    safeAddress: resolved.accountWallet,
    walletType: resolved.walletType,
    walletTypeName: resolved.walletTypeName,
    path,
    ready: Boolean(resolved.syncReady && (!resolved.needsDeploy || builderConfigured)),
    needsDeploy: Boolean(resolved.needsDeploy),
  };
  setSession(req.auth.userId, next);

  res.json({
    ...next,
    signer: eoa,
    syncReady: resolved.syncReady,
    builderConfigured,
    relayerConfigured,
    profile: resolved.profile,
    message: resolved.message,
  });
}));

/**
 * Import private key or seed into Privy for an existing Polymarket wallet.
 * Key is used once for import and is not persisted by Peak.
 */
app.post("/auth/import-wallet", wrap(async (req, res) => {
  if (req.auth.mode !== "privy") {
    return res.status(400).json({ error: "Sign in with Email / Apple / Google first, then import." });
  }
  if (!privy) {
    return res.status(503).json({ error: "Privy is not configured on the server." });
  }

  let keyForImport = "";
  try {
    keyForImport = await resolvePrivateKeyHex(req.body || {});
  } catch (e) {
    return res.status(400).json({ error: e?.message ?? String(e) });
  }

  let account;
  try {
    account = privateKeyToAccount(keyForImport);
  } catch (e) {
    return res.status(400).json({ error: `Invalid key: ${e?.message ?? e}` });
  }

  let imported;
  try {
    // User-owned import so the wallet appears on the Privy user and signs with their JWT.
    imported = await privy.wallets().import({
      wallet: {
        entropy_type: "private-key",
        chain_type: "ethereum",
        address: account.address,
        private_key: keyForImport,
      },
      owner: { user_id: req.auth.userId },
    });
  } catch (e) {
    const msg = String(e?.message ?? e);
    // Already imported for this user — reuse by address lookup.
    if (/already|exists|duplicate/i.test(msg)) {
      const found = await findSignableWalletForAddress(privy, req.auth.userId, account.address);
      if (found?.walletId) {
        imported = { id: found.walletId, address: found.address };
      } else {
        return res.status(502).json({
          error: "This wallet may already be linked. Sign out, sign in, and try Import again.",
          code: "import_failed",
        });
      }
    } else {
      console.warn("Privy import failed:", msg);
      return res.status(502).json({
        error: "Couldn’t import that wallet. Check the key or seed and try again.",
        code: "import_failed",
      });
    }
  }

  const address = imported?.address || account.address;
  const walletId = imported?.id ?? null;
  if (!walletId) {
    return res.status(502).json({
      error: "Import didn’t return a wallet id. Try again.",
      code: "import_failed",
    });
  }

  const resolved = await resolvePolymarketAccount({
    signer: address,
    path: "existing",
    accountWalletHint: null,
  });

  const session = {
    userId: req.auth.userId,
    eoa: address,
    accountWallet: resolved.accountWallet,
    safeAddress: resolved.accountWallet,
    walletType: resolved.walletType,
    walletTypeName: resolved.walletTypeName,
    path: "existing",
    ready: Boolean(resolved.syncReady),
    needsDeploy: false,
    imported: true,
    walletId,
    clobClient: null,
    _privyAuthJwt: null,
  };
  setSession(req.auth.userId, session);

  // Prove signing works before telling the client success.
  const userJwt = req.auth.accessToken;
  try {
    await ensureUserClob(session, { userJwt });
  } catch (e) {
    console.warn("import post-sign verify failed:", e?.message ?? e);
    const mapped = mapOrderError(extractClobError(e), { code: e?.code });
    return res.status(mapped.status || 401).json({
      error: mapped.error,
      code: mapped.code || "wallet_auth_failed",
      address,
      imported: true,
      needsImport: false,
    });
  }

  const fresh = getSession(req.auth.userId);
  res.json({
    address,
    signer: address,
    accountWallet: resolved.accountWallet,
    walletType: resolved.walletType,
    walletTypeName: resolved.walletTypeName,
    path: "existing",
    syncReady: resolved.syncReady,
    imported: true,
    needsImport: false,
    walletId,
    ready: Boolean(fresh?.ready),
    message: resolved.syncReady
      ? "Connected to your Polymarket account. Ready to trade."
      : "Wallet imported. Add your Polymarket profile address if positions are missing.",
  });
}));

/** @param {{ privateKey?: string, mnemonic?: string }} body */
async function resolvePrivateKeyHex(body) {
  const rawKey = String(body.privateKey || "").trim();
  const mnemonic = String(body.mnemonic || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");

  if (mnemonic.split(" ").filter(Boolean).length >= 12) {
    const { mnemonicToSeedSync } = await import("@scure/bip39");
    const { HDKey } = await import("@scure/bip32");
    const seed = mnemonicToSeedSync(mnemonic);
    const child = HDKey.fromMasterSeed(seed).derive("m/44'/60'/0'/0/0");
    if (!child.privateKey) {
      throw new Error("Could not derive private key from seed phrase.");
    }
    return `0x${Buffer.from(child.privateKey).toString("hex")}`;
  }

  if (/^(0x)?[0-9a-fA-F]{64}$/.test(rawKey)) {
    return rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`;
  }

  throw new Error("Provide a 64-char hex private key or a 12/24-word seed phrase.");
}

app.post("/trading/setup", wrap(async (req, res) => {
  if (req.auth.mode !== "privy") {
    return res.status(400).json({ error: "Privy session required" });
  }

  const session = getSession(req.auth.userId);
  if (!session?.eoa) {
    return res.status(400).json({ error: "Call POST /auth/session with eoa first" });
  }

  const resolved = await resolvePolymarketAccount({
    signer: session.eoa,
    path: session.path || "new",
    accountWalletHint: session.accountWallet,
  });

  Object.assign(session, {
    accountWallet: resolved.accountWallet,
    safeAddress: resolved.accountWallet,
    walletType: resolved.walletType,
    walletTypeName: resolved.walletTypeName,
    needsDeploy: resolved.needsDeploy,
    ready: Boolean(resolved.syncReady && !resolved.needsDeploy),
  });
  setSession(req.auth.userId, session);

  // Existing Polymarket account — link only; orders need Builder + signer.
  // Do not run deposit-wallet approvals here (usually already approved on PM).
  if (session.path === "existing" && resolved.syncReady) {
    if (builderConfigured) {
      try {
        await ensureUserClob(session, privySignOpts(req));
        const fresh = getSession(req.auth.userId);
        return res.json({
          ...toPublicSession(fresh),
          signer: session.eoa,
          syncReady: true,
          builderConfigured: true,
          relayerConfigured,
          needsImport: false,
          message: "Account linked. Ready to trade.",
          status: "linked_ready",
        });
      } catch (e) {
        if (isImportWalletError(e)) {
          return res.json({
            ...toPublicSession(session),
            signer: session.eoa,
            syncReady: true,
            builderConfigured: true,
            relayerConfigured,
            needsImport: true,
            code: "import_wallet_required",
            error:
              e.safeMessage ||
              "Import the private key or seed for this Polymarket wallet to enable trading.",
            message:
              e.safeMessage ||
              "Import the private key or seed for this Polymarket wallet to enable trading.",
            status: "linked_needs_import",
          });
        }
        const mapped = mapOrderError(e?.safeMessage || e?.message || e, { code: e?.code });
        return res.json({
          ...toPublicSession(session),
          signer: session.eoa,
          syncReady: true,
          builderConfigured: true,
          relayerConfigured,
          needsImport: false,
          code: mapped.code,
          message: mapped.error,
          status: "linked_builder_ready",
        });
      }
    }
    return res.json({
      ...toPublicSession(session),
      signer: session.eoa,
      syncReady: true,
      builderConfigured: false,
      relayerConfigured,
      needsImport: false,
      message: "Account linked. Add Builder credentials on the server to enable live orders.",
      status: "linked_pending_builder",
    });
  }

  if (!builderConfigured) {
    return res.status(503).json({
      error: "Trading isn’t ready yet. Try again in a moment.",
      code: "builder_not_ready",
      builderConfigured: false,
      relayerConfigured,
      needsDeploy: true,
      syncReady: false,
      signer: session.eoa,
      path: session.path,
      accountWallet: session.accountWallet ?? null,
      message: "Server is still finishing trading setup. Try again shortly.",
    });
  }

  if (!relayerConfigured) {
    // RelayClient auth is Builder-signed; RELAYER_* is advisory. Still warn so ops can fill keys.
    console.warn("trading/setup: RELAYER_API_KEY / RELAYER_API_KEY_ADDRESS unset (Builder-only auth)");
  }

  // New path: deploy Deposit Wallet via Relayer.
  try {
    const walletClient = await walletClientForSession(session, privySignOpts(req));
    const deploy = await deployOrLinkDepositWallet({
      walletClient,
      cfg: tradingCfg,
      alreadyDeployedAddress: resolved.accountWallet,
    });

    const next = {
      ...session,
      accountWallet: deploy.accountWallet,
      safeAddress: deploy.accountWallet,
      walletType: 3,
      walletTypeName: "DEPOSIT_WALLET",
      needsDeploy: false,
      ready: true,
    };
    setSession(req.auth.userId, next);

    let approvalsMessage = null;
    try {
      const approvals = await setupDepositWalletTradingApprovals({
        walletClient,
        cfg: tradingCfg,
        depositWalletAddress: deploy.accountWallet,
        rpcUrl: POLYGON_RPC_URL,
      });
      approvalsMessage = approvals.message;
    } catch (e) {
      console.warn("trading approvals after deploy failed:", e?.message ?? e);
      approvalsMessage =
        typeof e?.safeMessage === "string" && e.safeMessage.trim()
          ? e.safeMessage.trim()
          : "Deposit wallet ready. Trading approvals still pending — retry Set up trading.";
    }

    try {
      await ensureUserClob(next, privySignOpts(req));
    } catch (e) {
      console.warn("CLOB derive after deploy failed:", e?.message ?? e);
    }

    const fresh = getSession(req.auth.userId);
    return res.json({
      ...toPublicSession(fresh),
      signer: session.eoa,
      syncReady: true,
      builderConfigured: true,
      relayerConfigured,
      txHash: deploy.txHash,
      message: approvalsMessage ? `${deploy.message} ${approvalsMessage}` : deploy.message,
      status: deploy.status,
      approvalsMessage,
    });
  } catch (e) {
    console.error("trading/setup deploy failed:", e?.message ?? e);
    const status = Number(e?.httpStatus || e?.status) || 501;
    const code = e?.code || "setup_failed";
    const publicFields =
      e?.publicFields && typeof e.publicFields === "object" ? e.publicFields : {};
    return res.status(status).json({
      error:
        typeof e?.safeMessage === "string" && e.safeMessage.trim()
          ? e.safeMessage.trim()
          : "Couldn’t finish wallet setup. Try again.",
      code,
      builderConfigured,
      relayerConfigured,
      needsDeploy: true,
      syncReady: false,
      signer: session.eoa,
      path: session.path || "new",
      accountWallet: session.accountWallet ?? null,
      walletTypeName: "DEPOSIT_WALLET",
      status: "deploy_failed",
      message:
        typeof e?.safeMessage === "string" && e.safeMessage.trim()
          ? e.safeMessage.trim()
          : "Deposit wallet deploy failed. Check Privy wallet auth and Relayer, then retry.",
      ...publicFields,
    });
  }
}));

function toPublicSession(session) {
  if (!session) return {};
  const { clobClient, _privyAuthJwt, ...rest } = session;
  return rest;
}

app.get("/portfolio", wrap(async (req, res) => {
  if (req.auth.mode === "legacy") {
    const [positions, value, balance] = await Promise.all([
      getJSON(`${DATA}/positions?user=${FUNDER_ADDRESS}&sizeThreshold=0`),
      getJSON(`${DATA}/value?user=${FUNDER_ADDRESS}`).catch(() => null),
      legacyClient.getBalanceAllowance?.({ asset_type: AssetType.COLLATERAL }).catch(() => null),
    ]);
    const cashUSD = normalizeCollateralUSD(balance?.balance);
    return res.json({
      positions,
      value,
      balance,
      cashUSD,
      funder: FUNDER_ADDRESS,
      ready: true,
      syncReady: true,
      needsDeploy: false,
      builderConfigured,
      relayerConfigured,
    });
  }

  const session = getSession(req.auth.userId);
  const user = session?.accountWallet || session?.safeAddress || session?.eoa || req.query.user;
  if (!user) {
    return res.status(400).json({ error: "Call POST /auth/session with eoa first" });
  }
  const [positions, value] = await Promise.all([
    getJSON(`${DATA}/positions?user=${user}&sizeThreshold=0`),
    getJSON(`${DATA}/value?user=${user}`).catch(() => null),
  ]);

  let balance = null;
  let cashUSD = null;
  let cashError = null;
  let cashErrorCode = null;
  let needsImport = false;
  if (builderConfigured && session?.eoa) {
    try {
      const client = await ensureUserClob(session, privySignOpts(req));
      // signature_type is also injected by ClobClient from construction; pass explicitly for clarity.
      const sigType = Number(session.walletType ?? signatureTypeFromWalletName(session.walletTypeName, 3));
      const collateral = await fetchCollateralBalance(client, sigType);
      balance = collateral.raw;
      cashUSD = collateral.usd;
      if (cashUSD == null) {
        const mapped = mapCashError(
          collateral.error || { message: "cash_sync_failed", code: "cash_sync_failed" }
        );
        cashError = mapped.cashError;
        cashErrorCode = mapped.cashErrorCode;
        needsImport = mapped.needsImport;
      }
    } catch (e) {
      console.warn("portfolio balance:", e?.message ?? e);
      const mapped = mapCashError(e);
      cashError = mapped.cashError;
      cashErrorCode = mapped.cashErrorCode;
      needsImport = mapped.needsImport;
    }
  }

  const ready = Boolean(session?.ready);
  // Account linked when we have an account wallet (deposit / proxy / Safe / EOA book).
  // Do not alias `session.ready` — that can stay false when Builder/CLOB isn’t fully warm.
  const syncReady = Boolean(session?.accountWallet);
  res.json({
    positions,
    value,
    balance,
    cashUSD,
    cashError,
    cashErrorCode,
    needsImport,
    funder: user,
    signer: session?.eoa ?? null,
    accountWallet: session?.accountWallet ?? null,
    walletTypeName: session?.walletTypeName ?? null,
    path: session?.path ?? null,
    ready,
    syncReady,
    needsDeploy: Boolean(session?.needsDeploy),
    builderConfigured,
    relayerConfigured,
  });
}));

app.get("/activity", wrap(async (req, res) => {
  const limit = Math.min(Number(req.query.limit ?? 50), 100);
  if (req.auth.mode === "legacy") {
    return res.json(await getJSON(`${DATA}/activity?user=${FUNDER_ADDRESS}&limit=${limit}`));
  }
  const session = getSession(req.auth.userId);
  const user = session?.accountWallet || session?.safeAddress || session?.eoa;
  if (!user) return res.status(400).json({ error: "Call POST /auth/session with eoa first" });
  res.json(await getJSON(`${DATA}/activity?user=${user}&limit=${limit}`));
}));

app.get("/orders", wrap(async (req, res) => {
  if (req.auth.mode === "legacy") {
    const [open, trades] = await Promise.all([legacyClient.getOpenOrders(), legacyClient.getTrades()]);
    return res.json({ open, trades });
  }
  if (!builderConfigured) {
    return res.json({ open: [], trades: [], builderConfigured: false });
  }
  const session = getSession(req.auth.userId);
  if (!session?.eoa) {
    return res.status(400).json({ error: "Call POST /auth/session with eoa first" });
  }
  try {
    const client = await ensureUserClob(session, privySignOpts(req));
    const [open, trades] = await Promise.all([
      client.getOpenOrders(),
      client.getTrades?.() ?? Promise.resolve([]),
    ]);
    return res.json({ open, trades, builderConfigured: true });
  } catch (e) {
    const mapped = mapOrderError(e?.safeMessage || extractClobError(e), { code: e?.code });
    return res.status(e?.httpStatus || mapped.status || 501).json({
      error: e?.safeMessage || mapped.error,
      code: e?.code || mapped.code,
      builderConfigured: true,
    });
  }
}));

app.post("/orders", wrap(async (req, res) => {
  const body = req.body || {};
  const { tokenID, price, size, amount, side, orderType = "FOK", tickSize, negRisk } = body;

  if (!tokenID || price == null || size == null || !side) {
    return res.status(400).json({
      error: "tokenID, price, size, side required",
      code: "invalid_order",
    });
  }
  const priceN = Number(price);
  const sizeN = Number(size);
  if (!(priceN > 0 && priceN < 1) || !(sizeN > 0)) {
    return res.status(400).json({
      error: "Enter a valid USD amount and price between 0 and 1.",
      code: "invalid_order",
    });
  }

  if (req.auth.mode === "privy") {
    if (!builderConfigured) {
      return res.status(503).json({
        error: "Live trading needs Polymarket Builder credentials on the Peak backend. Add them, then try again.",
        code: "builder_not_ready",
      });
    }
    const session = getSession(req.auth.userId);
    if (!session?.eoa) {
      return res.status(400).json({
        error: "Call POST /auth/session with eoa first",
        code: "not_signed_in",
      });
    }
    if (session.needsDeploy && !session.accountWallet) {
      return res.status(400).json({
        error: "Finish trading setup first (deploy / link your deposit wallet), then place an order.",
        code: "setup_required",
        needsDeploy: true,
      });
    }

    let cashUSD = null;
    try {
      const client = await ensureUserClob(session, privySignOpts(req));
      const sigType = session.walletType ?? signatureTypeFromWalletName(session.walletTypeName, 3);
      const sideUpper = String(side).toUpperCase();
      const orderCostUSD =
        amount != null && Number(amount) > 0 && sideUpper === "BUY"
          ? Number(amount)
          : sizeN * priceN;

      if (sideUpper === "BUY") {
        const collateral = await fetchCollateralBalance(client, sigType);
        cashUSD = collateral.usd;
        if (cashUSD != null && cashUSD + 1e-9 < orderCostUSD) {
          return res.status(400).json({
            error: `Insufficient funds. You have $${cashUSD.toFixed(2)} available but this buy needs about $${orderCostUSD.toFixed(2)}. Deposit to your trading wallet, then try again.`,
            code: "insufficient_funds",
            balanceUSD: cashUSD,
            requiredUSD: orderCostUSD,
          });
        }
      } else {
        const conditional = await fetchConditionalBalance(client, tokenID, sigType);
        if (conditional.shares != null && conditional.shares + 1e-9 < sizeN) {
          return res.status(400).json({
            error: `Not enough shares to sell. You hold about ${conditional.shares.toFixed(2)} but tried to sell ${sizeN.toFixed(2)}.`,
            code: "insufficient_shares",
            balanceShares: conditional.shares,
            requiredShares: sizeN,
          });
        }
      }

      const result = await placeClobOrder(client, {
        tokenID,
        price: priceN,
        size: sizeN,
        amount,
        side,
        orderType,
        tickSize,
        negRisk,
      });
      return res.json({ ...result, success: result?.success !== false });
    } catch (e) {
      if (e?.code === "import_wallet_required" || e?.safeMessage) {
        const mapped = mapOrderError(e.safeMessage || extractClobError(e), {
          balanceUSD: cashUSD,
          code: e.code,
        });
        return res.status(e.httpStatus || mapped.status || 400).json({
          error: e.safeMessage || mapped.error,
          code: e.code || mapped.code,
          success: false,
          ...(e.publicFields && typeof e.publicFields === "object" ? e.publicFields : {}),
        });
      }
      const mapped = mapOrderError(extractClobError(e), {
        balanceUSD: cashUSD,
        code: e.code,
      });
      const status = e.httpStatus || mapped.status || 400;
      return res.status(status).json({
        error: e.code === "invalid_order" ? e.message : mapped.error,
        code: e.code || mapped.code,
        success: false,
        ...(e.clob ? { clob: e.clob } : {}),
      });
    }
  }

  // Legacy one-wallet proxy
  try {
    const result = await placeClobOrder(legacyClient, {
      tokenID,
      price: priceN,
      size: sizeN,
      amount,
      side,
      orderType,
      tickSize,
      negRisk,
    });
    return res.json({ ...result, success: result?.success !== false });
  } catch (e) {
    const mapped = mapOrderError(extractClobError(e));
    return res.status(e.httpStatus || mapped.status || 400).json({
      error: mapped.error,
      code: e.code || mapped.code,
      success: false,
    });
  }
}));

app.delete("/orders/:id", wrap(async (req, res) => {
  if (req.auth.mode === "privy") {
    if (!builderConfigured) {
      return res.status(503).json({ error: "Builder credentials required to cancel orders" });
    }
    const session = getSession(req.auth.userId);
    if (!session?.eoa) {
      return res.status(400).json({ error: "Call POST /auth/session with eoa first" });
    }
    const id = req.params.id;
    try {
      const client = await ensureUserClob(session, privySignOpts(req));
      try {
        return res.json(await client.cancelOrder(id));
      } catch {
        return res.json(await client.cancelOrder({ orderID: id }));
      }
    } catch (e) {
      const mapped = mapOrderError(e?.safeMessage || extractClobError(e), { code: e?.code });
      return res.status(e?.httpStatus || mapped.status || 501).json({
        error: e?.safeMessage || mapped.error,
        code: e?.code || mapped.code,
      });
    }
  }
  const id = req.params.id;
  try {
    res.json(await legacyClient.cancelOrder(id));
  } catch {
    res.json(await legacyClient.cancelOrder({ orderID: id }));
  }
}));

app.post("/deposit-address", wrap(async (req, res) => {
  const chain = String(req.body?.chain || "polygon").toLowerCase();
  const token = String(req.body?.token || "USDC").toUpperCase();

  let funder = FUNDER_ADDRESS;
  let session = null;
  if (req.auth.mode === "privy") {
    session = getSession(req.auth.userId);
    funder = session?.accountWallet || session?.safeAddress || null;
    if (!session?.eoa) {
      return res.status(400).json({
        error: "Sign in and set up trading first.",
        code: "setup_required",
      });
    }
    // Prefer account wallet; for existing path allow EOA when account wallet isn't linked yet.
    if (!funder) {
      funder = session.path === "existing" ? session.eoa : null;
    }
    // New path without a deploy yet: try a soft derive so deposit isn't blocked after a partial setup.
    if (!funder && session.path === "new" && builderConfigured) {
      try {
        const walletClient = await walletClientForSession(session, privySignOpts(req));
        const soft = await deployOrLinkDepositWallet({
          walletClient,
          cfg: tradingCfg,
          alreadyDeployedAddress: session.accountWallet || null,
        });
        if (soft?.accountWallet) {
          funder = soft.accountWallet;
          const next = {
            ...session,
            accountWallet: soft.accountWallet,
            safeAddress: soft.accountWallet,
            walletType: 3,
            walletTypeName: "DEPOSIT_WALLET",
            needsDeploy: false,
            ready: true,
          };
          setSession(req.auth.userId, next);
          session = next;
        }
      } catch (e) {
        console.warn("deposit-address soft setup failed:", e?.message ?? e);
      }
    }
    if (!funder && session?.needsDeploy && !session?.accountWallet) {
      return res.status(400).json({
        error: "Finish Set up trading first, then request a deposit address.",
        code: "setup_required",
        needsDeploy: true,
        syncReady: false,
        builderConfigured,
        relayerConfigured,
      });
    }
    if (!funder) {
      return res.status(400).json({
        error: "Finish Set up trading first, then request a deposit address.",
        code: "setup_required",
        needsDeploy: Boolean(session?.needsDeploy),
        syncReady: false,
        builderConfigured,
        relayerConfigured,
      });
    }
  }

  if (!funder) {
    return res.status(400).json({
      error: "No trading wallet configured for deposits.",
      code: "setup_required",
    });
  }

  try {
    const bridge = await fetchBridgeDepositAddresses(funder);
    const depositAddress = pickBridgeAddress(bridge, chain);
    const address = depositAddress || funder;
    return res.json({
      ...bridge,
      // Always flatten to a string so iOS never has to dig nested Bridge shapes.
      address,
      depositAddress: address,
      funder,
      accountWallet: funder,
      chain,
      token,
      note:
        bridge?.note ||
        "Send only supported assets. Cross-chain deposits use the bridge address; Polygon pUSD may credit the funder directly.",
      needsDeploy: Boolean(session?.needsDeploy),
      syncReady: true,
      builderConfigured,
      relayerConfigured,
    });
  } catch (e) {
    console.warn("deposit-address bridge failed:", e?.message ?? e);
    // Fallback: return funder so same-chain funding still works if Bridge is down.
    return res.json({
      address: funder,
      depositAddress: funder,
      funder,
      accountWallet: funder,
      chain,
      token,
      note: session?.accountWallet
        ? "Bridge temporarily unavailable — showing your trading wallet for same-chain funding."
        : "Bridge temporarily unavailable — showing your wallet address for same-chain funding.",
      needsDeploy: Boolean(session?.needsDeploy),
      syncReady: Boolean(funder),
      builderConfigured,
      relayerConfigured,
    });
  }
}));

/** @param {string} polymarketWallet */
async function fetchBridgeDepositAddresses(polymarketWallet) {
  return getJSON(`${BRIDGE}/deposit`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(POLY_BUILDER_CODE ? { "X-Builder-Code": POLY_BUILDER_CODE } : {}),
    },
    body: JSON.stringify({ address: polymarketWallet }),
  });
}

/**
 * Pick a concrete deposit address from Bridge response for the requested chain.
 * @param {any} bridge
 * @param {string} chain
 */
function pickBridgeAddress(bridge, chain) {
  const c = String(chain || "").toLowerCase();
  const addr = bridge?.address;
  if (typeof addr === "string" && addr) return addr;
  if (addr && typeof addr === "object") {
    if (c === "solana" || c === "svm") return addr.svm || null;
    if (c === "bitcoin" || c === "btc") return addr.btc || null;
    if (c === "tron" || c === "tvm") return addr.tvm || null;
    return addr.evm || null;
  }
  if (typeof bridge?.depositAddress === "string") return bridge.depositAddress;
  return null;
}

// Avoid leaking stack traces; map CORS denials to 403.
app.use((err, _req, res, _next) => {
  if (err?.message === "CORS origin not allowed") {
    return res.status(403).json({ error: "CORS origin not allowed", code: "cors_denied" });
  }
  console.error(err?.message ?? err);
  res.status(500).json({ error: "Internal error. Try again.", code: "internal_error" });
});

initLegacyClient()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`Peak trading API on :${PORT}`);
      console.log(
        `  legacy=${legacyEnabled} privy=${privyEnabled} builder=${builderConfigured} relayer=${relayerConfigured}`
      );
      console.log(
        `  cors=${corsOrigins.length ? corsOrigins.join("|") : "off"} rateLimit=${maxReqs}/${windowMs}ms`
      );
    });
  })
  .catch((e) => {
    console.error("Init failed:", e);
    process.exit(1);
  });
