/**
 * File-backed session metadata (no CLOB secrets).
 * In-memory Map holds live session + optional clobClient.
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const STORE_PATH = process.env.PEAK_SESSION_STORE || path.join(__dirname, ".sessions.json");

/** @type {Map<string, object>} */
const memory = new Map();

const PERSIST_KEYS = [
  "userId",
  "eoa",
  "accountWallet",
  "safeAddress",
  "walletType",
  "walletTypeName",
  "path",
  "ready",
  "needsDeploy",
  "imported",
  "walletId",
];

function toPersistable(session) {
  const out = {};
  for (const k of PERSIST_KEYS) {
    if (session[k] !== undefined) out[k] = session[k];
  }
  return out;
}

export function loadSessions() {
  try {
    if (!fs.existsSync(STORE_PATH)) return;
    const raw = JSON.parse(fs.readFileSync(STORE_PATH, "utf8"));
    for (const [k, v] of Object.entries(raw)) {
      memory.set(k, v);
    }
    console.log(`Loaded ${memory.size} trading session(s) from disk`);
  } catch (e) {
    console.warn("Session store load failed:", e?.message ?? e);
  }
}

function persist() {
  try {
    const obj = {};
    for (const [k, v] of memory.entries()) {
      obj[k] = toPersistable(v);
    }
    fs.writeFileSync(STORE_PATH, JSON.stringify(obj, null, 2));
  } catch (e) {
    console.warn("Session store save failed:", e?.message ?? e);
  }
}

export function getSession(userId) {
  return memory.get(userId);
}

export function setSession(userId, session) {
  const prev = memory.get(userId) || {};
  const next = { ...prev, ...session, userId };
  // Keep non-persistable runtime fields if present
  if (session.clobClient) next.clobClient = session.clobClient;
  else if (prev.clobClient && !session.clobClient) next.clobClient = prev.clobClient;
  memory.set(userId, next);
  persist();
  return next;
}

export function deleteSession(userId) {
  memory.delete(userId);
  persist();
}

export { memory as sessions };
