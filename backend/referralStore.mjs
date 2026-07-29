/**
 * Referral codes and a cosmetic points ledger. Uses node:sqlite (built into
 * Node core since 22.13 — no native module, no compiler needed on the Alpine
 * image this backend ships on, unlike better-sqlite3).
 *
 * Points here have no redeemable value by design — see the Terms. Awarding
 * happens only from awardMilestone(), called once a referred user's first
 * trade actually succeeds, not at redeem time. That single rule is what stops
 * this being trivially farmed with throwaway accounts.
 */
import { DatabaseSync } from "node:sqlite";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Referrer bonus for a friend's first successful trade; the friend's own
// welcome bonus for the same event. Cosmetic numbers — easy to retune.
export const REFERRER_BONUS = 100;
export const REFERRED_BONUS = 50;

function resolveDbPath(raw) {
  const fallback = path.join(__dirname, ".referrals.db");
  if (!raw || !String(raw).trim()) return fallback;
  const resolved = path.resolve(String(raw).trim());
  try {
    if (fs.existsSync(resolved) && fs.statSync(resolved).isDirectory()) {
      return path.join(resolved, "referrals.db");
    }
  } catch {
    // fall through
  }
  // Mirrors sessionStore.mjs: a volume mounted at /data before any file
  // exists there yet should still be treated as a directory.
  if (resolved === "/data" || resolved.endsWith(`${path.sep}data`)) {
    return path.join(resolved, "referrals.db");
  }
  return resolved;
}

// Same env var family as the session store — same Railway volume, one
// variable per file so either can move independently later if needed.
const DB_PATH = process.env.PEAK_REFERRAL_STORE
  ? resolveDbPath(process.env.PEAK_REFERRAL_STORE)
  : resolveDbPath(process.env.PEAK_SESSION_STORE);

function ensureParentDir(p) {
  const dir = path.dirname(p);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}
ensureParentDir(DB_PATH);

const db = new DatabaseSync(DB_PATH);
db.exec("PRAGMA journal_mode = WAL");
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    privy_user_id TEXT PRIMARY KEY,
    referral_code TEXT UNIQUE NOT NULL,
    referred_by TEXT REFERENCES users(privy_user_id),
    created_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS points_ledger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    delta INTEGER NOT NULL,
    reason TEXT NOT NULL,
    related_user_id TEXT,
    created_at INTEGER NOT NULL,
    UNIQUE(user_id, reason, related_user_id)
  );
`);

// Excludes 0/O/1/I/L — a misread code is a support ticket, not a typo.
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

function generateCode() {
  let out = "";
  const bytes = crypto.randomBytes(7);
  for (let i = 0; i < 7; i++) {
    out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  }
  return out;
}

function codeExists(code) {
  return !!db.prepare("SELECT 1 FROM users WHERE referral_code = ?").get(code);
}

function findUser(privyUserId) {
  return db.prepare("SELECT * FROM users WHERE privy_user_id = ?").get(privyUserId);
}

/** Fetch this user's referral code, creating their row (and a fresh code) on first call. */
export function getOrCreateCode(privyUserId) {
  const existing = findUser(privyUserId);
  if (existing) return existing.referral_code;

  let code = generateCode();
  // Collision odds are astronomically low at this alphabet/length, but a
  // silent duplicate code would let two people share one identity — check.
  while (codeExists(code)) code = generateCode();

  db.prepare(
    "INSERT INTO users (privy_user_id, referral_code, referred_by, created_at) VALUES (?, ?, NULL, ?)"
  ).run(privyUserId, code, Date.now());
  return code;
}

export class ReferralError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

/**
 * Link `privyUserId` to whoever owns `code`. No points move here — see
 * awardMilestone(). Idempotent-safe to call once; a second call for the same
 * user is rejected, not silently re-applied.
 */
export function redeemCode(privyUserId, code) {
  const trimmed = String(code || "").trim().toUpperCase();
  if (!trimmed) throw new ReferralError("invalid_code", "Enter a code.");

  const owner = db.prepare("SELECT * FROM users WHERE referral_code = ?").get(trimmed);
  if (!owner) throw new ReferralError("code_not_found", "That code doesn't match anyone.");
  if (owner.privy_user_id === privyUserId) {
    throw new ReferralError("self_referral", "You can't use your own code.");
  }

  const self = findUser(privyUserId);
  if (self?.referred_by) {
    throw new ReferralError("already_referred", "You've already used a referral code.");
  }

  if (self) {
    db.prepare("UPDATE users SET referred_by = ? WHERE privy_user_id = ?").run(
      owner.privy_user_id,
      privyUserId
    );
  } else {
    db.prepare(
      "INSERT INTO users (privy_user_id, referral_code, referred_by, created_at) VALUES (?, ?, ?, ?)"
    ).run(privyUserId, generateCode(), owner.privy_user_id, Date.now());
  }
  return { referrerId: owner.privy_user_id };
}

function credit(userId, delta, reason, relatedUserId) {
  try {
    db.prepare(
      "INSERT INTO points_ledger (user_id, delta, reason, related_user_id, created_at) VALUES (?, ?, ?, ?, ?)"
    ).run(userId, delta, reason, relatedUserId ?? null, Date.now());
    return true;
  } catch (e) {
    // UNIQUE(user_id, reason, related_user_id) — this exact bonus was already
    // paid out. That is the intended, expected outcome on a retry, not a bug.
    if (String(e?.message || "").includes("UNIQUE")) return false;
    throw e;
  }
}

/**
 * Award the one-time referral bonus pair once `referredUserId`'s first trade
 * actually succeeds. Safe to call on every trade — after the first successful
 * award the unique constraint makes every later call a no-op.
 */
export function awardMilestone(referredUserId) {
  const referred = findUser(referredUserId);
  if (!referred?.referred_by) return { awarded: false };

  const referrerCredited = credit(
    referred.referred_by,
    REFERRER_BONUS,
    "referral_bonus",
    referredUserId
  );
  const referredCredited = credit(
    referredUserId,
    REFERRED_BONUS,
    "referred_bonus",
    referred.referred_by
  );
  return { awarded: referrerCredited || referredCredited };
}

export function getBalance(privyUserId) {
  const row = db
    .prepare("SELECT COALESCE(SUM(delta), 0) AS total FROM points_ledger WHERE user_id = ?")
    .get(privyUserId);
  return row.total;
}

export function getHistory(privyUserId, limit = 20) {
  return db
    .prepare(
      "SELECT delta, reason, related_user_id, created_at FROM points_ledger WHERE user_id = ? ORDER BY created_at DESC LIMIT ?"
    )
    .all(privyUserId, limit);
}

export { DB_PATH as referralStorePath };
