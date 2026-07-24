// Peak trading proxy — Polymarket CLOB V2.
// Holds PRIVATE_KEY / CLOB creds so the iOS app never stores a trading key.
import "dotenv/config";
import express from "express";
import { ClobClient, Side, OrderType, SignatureTypeV2 } from "@polymarket/clob-client-v2";
import { createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";

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
} = process.env;

if (!APP_TOKEN || !PRIVATE_KEY || !FUNDER_ADDRESS) {
  console.error("Missing APP_TOKEN / PRIVATE_KEY / FUNDER_ADDRESS in .env");
  process.exit(1);
}

const HOST = "https://clob.polymarket.com";
const DATA = "https://data-api.polymarket.com";
const CHAIN_ID = 137;

const account = privateKeyToAccount(PRIVATE_KEY);
const signer = createWalletClient({ account, transport: http() });

let client;

async function initClient() {
  let creds =
    CLOB_API_KEY && CLOB_API_SECRET && CLOB_API_PASSPHRASE
      ? { key: CLOB_API_KEY, secret: CLOB_API_SECRET, passphrase: CLOB_API_PASSPHRASE }
      : undefined;

  if (!creds) {
    const temp = new ClobClient({ host: HOST, chain: CHAIN_ID, signer });
    creds = await temp.createOrDeriveApiKey();
    console.log("Derived CLOB API key:", creds.key);
  }

  const signatureType =
    Number(SIGNATURE_TYPE) === 3 ? SignatureTypeV2.POLY_1271 : Number(SIGNATURE_TYPE);

  client = new ClobClient({
    host: HOST,
    chain: CHAIN_ID,
    signer,
    creds,
    signatureType,
    funderAddress: FUNDER_ADDRESS,
  });

  console.log("CLOB ready. Funder:", FUNDER_ADDRESS, "Signer:", account.address);
}

const app = express();
app.use(express.json());
app.use((req, res, next) => {
  if (req.headers.authorization !== `Bearer ${APP_TOKEN}`) {
    return res.status(401).json({ error: "unauthorized" });
  }
  next();
});

const wrap = (fn) => (req, res) =>
  fn(req, res).catch((e) => {
    console.error(e);
    res.status(500).json({ error: String(e?.message ?? e) });
  });

const getJSON = async (url) => {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url} → ${r.status}: ${await r.text()}`);
  return r.json();
};

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    funder: FUNDER_ADDRESS,
    signer: account.address,
    builder: Boolean(POLY_BUILDER_CODE),
  });
});

app.get("/portfolio", wrap(async (_req, res) => {
  const [positions, value, balance] = await Promise.all([
    getJSON(`${DATA}/positions?user=${FUNDER_ADDRESS}&sizeThreshold=0`),
    getJSON(`${DATA}/value?user=${FUNDER_ADDRESS}`).catch(() => null),
    client.getBalanceAllowance?.({ asset_type: "COLLATERAL" }).catch(() => null),
  ]);
  res.json({ positions, value, balance, funder: FUNDER_ADDRESS });
}));

app.get("/activity", wrap(async (req, res) => {
  const limit = Math.min(Number(req.query.limit ?? 50), 100);
  res.json(await getJSON(`${DATA}/activity?user=${FUNDER_ADDRESS}&limit=${limit}`));
}));

app.get("/orders", wrap(async (_req, res) => {
  const [open, trades] = await Promise.all([client.getOpenOrders(), client.getTrades()]);
  res.json({ open, trades });
}));

app.post("/orders", wrap(async (req, res) => {
  const { tokenID, price, size, side, orderType = "FOK", tickSize, negRisk } = req.body;
  if (!tokenID || price == null || size == null || !side) {
    return res.status(400).json({ error: "tokenID, price, size, side required" });
  }

  const [resolvedTick, resolvedNegRisk] = await Promise.all([
    tickSize ?? client.getTickSize(tokenID),
    negRisk ?? client.getNegRisk(tokenID),
  ]);

  const response = await client.createAndPostOrder(
    {
      tokenID,
      price: Number(price),
      size: Number(size),
      side: String(side).toUpperCase() === "SELL" ? Side.SELL : Side.BUY,
      ...(POLY_BUILDER_CODE ? { builderCode: POLY_BUILDER_CODE } : {}),
    },
    { tickSize: String(resolvedTick), negRisk: Boolean(resolvedNegRisk) },
    OrderType[orderType] ?? OrderType.FOK,
  );

  res.json(response);
}));

app.delete("/orders/:id", wrap(async (req, res) => {
  res.json(await client.cancelOrder(req.params.id));
}));

initClient()
  .then(() => app.listen(PORT, () => console.log(`Peak trading proxy on :${PORT}`)))
  .catch((e) => {
    console.error("Client init failed:", e);
    process.exit(1);
  });
