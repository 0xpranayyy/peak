/**
 * File-backed session metadata (no CLOB secrets).
 * In-memory Map holds live session + optional clobClient.
 *
 * PEAK_SESSION_STORE may be a file path OR a directory (Railway volume mount).
 * If a directory is given, we write `sessions.json` inside it.
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function resolveStorePath(raw) {
  const fallback = path.join(__dirname, ".sessions.json");
  if (!raw || !String(raw).trim()) return fallback;
  const resolved = path.resolve(String(raw).trim());
  try {
    if (fs.existsSync(resolved) && fs.statSync(resolved).isDirectory()) {
      return path.join(resolved, "sessions.json");
    }
  } catch {
    // fall through
  }
  // Env often set to "/data" before the file exists — treat bare volume roots as dirs.
  if (resolved === "/data" || resolved.endsWith(`${path.sep}data`)) {
    return path.join(resolved, "sessions.json");
  }
  return resolved;
}

const STORE_PATH = resolveStorePath(process.env.PEAK_SESSION_STORE);

/** @type {Map<string, object>} */
const memory = new Map();

const PERSIST_KEYS = [
  "userId",
  "eoa",
  "loginEoa",
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

function ensureParentDir() {
  const dir = path.dirname(STORE_PATH);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

export function loadSessions() {
  try {
    if (!fs.existsSync(STORE_PATH)) return;
    if (fs.statSync(STORE_PATH).isDirectory()) {
      console.warn(`Session store path is a directory (${STORE_PATH}); expected a JSON file`);
      return;
    }
    const raw = JSON.parse(fs.readFileSync(STORE_PATH, "utf8"));
    for (const [k, v] of Object.entries(raw)) {
      memory.set(k, v);
    }
    console.log(`Loaded ${memory.size} trading session(s) from ${STORE_PATH}`);
  } catch (e) {
    console.warn("Session store load failed:", e?.message ?? e);
  }
}

function persist() {
  try {
    ensureParentDir();
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
  // Runtime-only fields: keep prior value unless the patch sets them explicitly
  // (including explicit `null` to clear after re-import / wallet change).
  if (Object.prototype.hasOwnProperty.call(session, "clobClient")) {
    if (session.clobClient) next.clobClient = session.clobClient;
    else delete next.clobClient;
  } else if (prev.clobClient) {
    next.clobClient = prev.clobClient;
  }
  if (Object.prototype.hasOwnProperty.call(session, "_privyAuthJwt")) {
    if (session._privyAuthJwt) next._privyAuthJwt = session._privyAuthJwt;
    else delete next._privyAuthJwt;
  } else if (prev._privyAuthJwt) {
    next._privyAuthJwt = prev._privyAuthJwt;
  }
  memory.set(userId, next);
  persist();
  return next;
}

export function deleteSession(userId) {
  memory.delete(userId);
  persist();
}

export { memory as sessions, STORE_PATH as sessionStorePath };
