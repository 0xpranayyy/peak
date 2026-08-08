/**
 * Peak trading API client (browser).
 *
 * Authenticated calls go to the Worker-fronted API host (`api.peakapp.site`)
 * with CORS. That skips Cloudflare Pages Functions (`/api/peak/*`), which
 * intermittently return raw CF 502s under load. Market data stays on
 * `edge.peakapp.site` via `lib/gamma.ts` / `lib/clob.ts`.
 *
 * Secrets (edge / Builder / Relayer) stay on the Worker + Railway — the
 * browser only sends the Privy JWT.
 */

const PEAK_API_BASE = (
  process.env.NEXT_PUBLIC_PEAK_API_URL ?? "https://api.peakapp.site"
).replace(/\/$/, "");

const RETRYABLE_STATUS = new Set([502, 503, 504]);

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export class PeakApiError extends Error {
  status: number;
  code: string | null;
  body: Record<string, unknown>;

  constructor(
    message: string,
    status: number,
    code: string | null,
    body: Record<string, unknown> = {}
  ) {
    super(message);
    this.name = "PeakApiError";
    this.status = status;
    this.code = code;
    this.body = body;
  }
}

function isRetryableError(err: unknown): boolean {
  if (err instanceof PeakApiError) return RETRYABLE_STATUS.has(err.status);
  // fetch() network failures are TypeError in browsers.
  return err instanceof TypeError;
}

async function parseJson(response: Response): Promise<Record<string, unknown>> {
  const text = await response.text();
  if (!text) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object" ? (parsed as Record<string, unknown>) : {};
  } catch {
    return { error: text };
  }
}

function friendlyApiMessage(json: Record<string, unknown>, status: number): string {
  const code = typeof json.code === "string" ? json.code : null;
  const raw =
    (typeof json.error === "string" && json.error) ||
    (typeof json.errorMsg === "string" && json.errorMsg) ||
    (typeof json.message === "string" && json.message) ||
    null;

  switch (code) {
    case "region_restricted":
      // Prefer short submit-time copy even if an older backend still sends
      // longer region prose.
      return String(json.regionStatus || "").toLowerCase() === "close_only"
        ? "New positions aren’t available here."
        : "Trading isn’t available here.";
    case "insufficient_funds":
      return raw || "Not enough cash for this order.";
    case "insufficient_shares":
      return raw || "Not enough shares to sell.";
    case "setup_required":
      return raw || "Finish trading setup first, then place an order.";
    case "builder_not_ready":
      return raw || "Live trading isn’t configured on the Peak backend yet.";
    case "import_wallet_required":
      return "This Polymarket wallet needs a key import in the Peak iOS app.";
    case "market_closed":
      return raw || "This market is no longer accepting orders.";
    case "invalid_order":
      return raw || "Enter a valid size and a price between 1¢ and 99¢.";
    case "edge_required":
      return raw || "Orders must go through Peak’s edge. Try again in a moment.";
    case "not_signed_in":
      return raw || "Sign in again, then retry.";
    case "no_fill":
      return raw || "No fill at that price. Try a market order or adjust your limit.";
    case "clob_unreachable":
      return (
        raw ||
        "Couldn’t reach the order book from this network. Try again on an allowed connection, or use the Peak iOS app."
      );
    default:
      break;
  }

  if (status === 502 || status === 503 || status === 504) {
    return "Couldn’t reach Peak. Retry";
  }

  if (raw) {
    const lower = raw.toLowerCase();
    if (
      lower.includes("user rejected") ||
      lower.includes("user denied") ||
      lower.includes("rejected the request") ||
      lower.includes("request rejected")
    ) {
      return "Signature cancelled in your wallet. Approve the request to continue.";
    }
    if (
      lower.includes("wrong network") ||
      lower.includes("chain mismatch") ||
      lower.includes("unsupported chain") ||
      lower.includes("switch to polygon")
    ) {
      return "Switch your wallet to Polygon (chain id 137), then try again.";
    }
    // Cloudflare Pages / Worker plain-text bodies like "error code: 502".
    if (/error code:\s*50[234]/i.test(lower) || lower === "bad gateway") {
      return "Couldn’t reach Peak. Retry";
    }
  }

  return raw || `Request failed (${status})`;
}

/** Map wallet / Privy client errors into short trader-facing copy. */
export function friendlyClientError(err: unknown): string {
  if (err instanceof PeakApiError) return err.message;
  const raw = err instanceof Error ? err.message : String(err ?? "Something went wrong.");
  const lower = raw.toLowerCase();
  if (
    lower.includes("user rejected") ||
    lower.includes("user denied") ||
    lower.includes("rejected the request") ||
    lower.includes("request rejected") ||
    lower.includes("action_rejected")
  ) {
    return "Signature cancelled in your wallet. Approve the request to continue.";
  }
  if (
    lower.includes("wrong network") ||
    lower.includes("chain mismatch") ||
    lower.includes("unsupported chain") ||
    lower.includes("switch network") ||
    lower.includes("switch chain")
  ) {
    return "Switch your wallet to Polygon (chain id 137), then try again.";
  }
  if (lower.includes("approval") && (lower.includes("denied") || lower.includes("reject"))) {
    return "Approval cancelled. Confirm the wallet prompt to continue.";
  }
  return raw || "Something went wrong.";
}

async function peakFetchOnce(
  path: string,
  options: {
    method?: string;
    token?: string | null;
    body?: Record<string, unknown>;
    query?: Record<string, string | number | undefined>;
  }
): Promise<Record<string, unknown>> {
  const url = new URL(path.replace(/^\//, ""), `${PEAK_API_BASE}/`);
  if (options.query) {
    for (const [key, value] of Object.entries(options.query)) {
      if (value !== undefined) url.searchParams.set(key, String(value));
    }
  }

  const headers: Record<string, string> = { accept: "application/json" };
  if (options.token) {
    headers.authorization = `Bearer ${options.token}`;
    headers["x-peak-auth"] = "privy";
  }
  if (options.body) headers["content-type"] = "application/json";

  let response: Response;
  try {
    response = await fetch(url.toString(), {
      method: options.method ?? (options.body ? "POST" : "GET"),
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
      cache: "no-store",
    });
  } catch {
    throw new PeakApiError("Couldn’t reach Peak. Retry", 503, "network_error");
  }

  const json = await parseJson(response);
  if (!response.ok) {
    throw new PeakApiError(
      friendlyApiMessage(json, response.status),
      response.status,
      typeof json.code === "string" ? json.code : null,
      json
    );
  }
  return json;
}

/** Silent retries on transient gateway / network failures (1–2 extras). */
export async function peakFetch(
  path: string,
  options: {
    method?: string;
    token?: string | null;
    body?: Record<string, unknown>;
    query?: Record<string, string | number | undefined>;
  } = {}
): Promise<Record<string, unknown>> {
  const attempts = 3;
  let last: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await peakFetchOnce(path, options);
    } catch (err) {
      last = err;
      if (!isRetryableError(err) || i === attempts - 1) throw err;
      await sleep(300 * (i + 1));
    }
  }
  throw last;
}

export type TradingSession = {
  eoa: string;
  accountWallet: string | null;
  safeAddress: string | null;
  walletTypeName: string | null;
  path: string | null;
  ready: boolean;
  syncReady: boolean;
  needsDeploy: boolean;
  builderConfigured?: boolean;
  message?: string | null;
};

export async function syncSession(
  token: string,
  eoa: string,
  path?: "new" | "existing"
): Promise<TradingSession> {
  const body: Record<string, unknown> = { eoa };
  // Omit path so the backend keeps an existing linked path (iOS import /
  // returning users). First-time sessions still default to "new" server-side.
  if (path) body.path = path;
  const root = await peakFetch("auth/session", {
    method: "POST",
    token,
    body,
  });
  return mapSession(root);
}

export async function setupTrading(token: string): Promise<TradingSession> {
  const root = await peakFetch("trading/setup", { method: "POST", token, body: {} });
  return mapSession(root);
}

export async function fetchPortfolio(token: string): Promise<PortfolioSnapshot> {
  const root = await peakFetch("portfolio", { token });
  const positions = Array.isArray(root.positions)
    ? (root.positions as Record<string, unknown>[])
    : [];
  return {
    cashUSD: typeof root.cashUSD === "number" ? root.cashUSD : null,
    cashError: typeof root.cashError === "string" ? root.cashError : null,
    funder: typeof root.funder === "string" ? root.funder : null,
    accountWallet:
      typeof root.accountWallet === "string" ? root.accountWallet : null,
    signer: typeof root.signer === "string" ? root.signer : null,
    ready: root.ready === true,
    syncReady: root.syncReady === true,
    needsDeploy: root.needsDeploy === true,
    needsImport: root.needsImport === true,
    positions: positions.map(mapPosition).filter((p): p is Position => p !== null),
  };
}

export type Position = {
  title: string;
  outcome: string;
  size: number;
  avgPrice: number | null;
  curPrice: number | null;
  cashPnl: number | null;
  eventSlug: string | null;
  /** CLOB asset / token id when present — used to deep-link a sell. */
  asset: string | null;
};

export type PortfolioSnapshot = {
  cashUSD: number | null;
  cashError: string | null;
  funder: string | null;
  accountWallet: string | null;
  signer: string | null;
  ready: boolean;
  syncReady: boolean;
  needsDeploy: boolean;
  needsImport: boolean;
  positions: Position[];
};

export type OpenOrder = {
  id: string;
  tokenID: string;
  market: string | null;
  side: string;
  price: number;
  originalSize: number;
  sizeMatched: number;
  status: string | null;
};

export async function fetchOpenOrders(token: string): Promise<OpenOrder[]> {
  const root = await peakFetch("orders", { token });
  const rows = Array.isArray(root.open) ? (root.open as Record<string, unknown>[]) : [];
  return rows.map(mapOpenOrder).filter((o): o is OpenOrder => o !== null);
}

export type ActivityItem = {
  id: string;
  title: string;
  outcome: string | null;
  type: string;
  side: string | null;
  size: number;
  price: number;
  usdcSize: number;
  timestamp: number | null;
  eventSlug: string | null;
};

/** Polymarket activity feed for the linked account wallet (real fills / redeems). */
export async function fetchActivity(
  token: string,
  limit = 25
): Promise<ActivityItem[]> {
  const attempts = 3;
  let last: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      const url = new URL("activity", `${PEAK_API_BASE}/`);
      url.searchParams.set("limit", String(limit));
      let response: Response;
      try {
        response = await fetch(url.toString(), {
          headers: {
            accept: "application/json",
            authorization: `Bearer ${token}`,
            "x-peak-auth": "privy",
          },
          cache: "no-store",
        });
      } catch {
        throw new PeakApiError("Couldn’t reach Peak. Retry", 503, "network_error");
      }
      const text = await response.text();
      let parsed: unknown = [];
      try {
        parsed = text ? JSON.parse(text) : [];
      } catch {
        parsed = [];
      }
      if (!response.ok) {
        const body =
          parsed && typeof parsed === "object" && !Array.isArray(parsed)
            ? (parsed as Record<string, unknown>)
            : {};
        throw new PeakApiError(
          friendlyApiMessage(body, response.status),
          response.status,
          typeof body.code === "string" ? body.code : null,
          body
        );
      }
      const rows = Array.isArray(parsed) ? (parsed as Record<string, unknown>[]) : [];
      return rows.map(mapActivity).filter((a): a is ActivityItem => a !== null);
    } catch (err) {
      last = err;
      if (!isRetryableError(err) || i === attempts - 1) throw err;
      await sleep(300 * (i + 1));
    }
  }
  throw last;
}

export async function cancelOrder(token: string, orderId: string): Promise<void> {
  await peakFetch(`orders/${encodeURIComponent(orderId)}`, {
    method: "DELETE",
    token,
  });
}

export async function fetchDepositAddress(
  token: string,
  chain = "polygon",
  depositToken = "USDC"
): Promise<string | null> {
  const root = await peakFetch("deposit-address", {
    method: "POST",
    token,
    body: { chain, token: depositToken },
  });
  return (
    (typeof root.depositAddress === "string" && root.depositAddress) ||
    (typeof root.address === "string" && root.address) ||
    (typeof root.funder === "string" && root.funder) ||
    (typeof root.accountWallet === "string" && root.accountWallet) ||
    null
  );
}

export type PreparedOrder = {
  url: string;
  headers: Record<string, string>;
  /** Exact JSON string from prepare — must be sent verbatim for L2 HMAC. */
  body: string;
};

export async function prepareOrder(
  token: string,
  order: {
    tokenID: string;
    price: number;
    size: number;
    side: "BUY" | "SELL";
    amount?: number;
    orderType?: string;
    negRisk?: boolean;
  }
): Promise<PreparedOrder> {
  const root = await peakFetch("orders/prepare", {
    method: "POST",
    token,
    body: order,
  });
  const url = typeof root.url === "string" ? root.url : null;
  const body = typeof root.body === "string" ? root.body : null;
  const headers =
    root.headers && typeof root.headers === "object"
      ? (root.headers as Record<string, string>)
      : null;
  if (!url || !body || !headers) {
    throw new PeakApiError("Couldn’t prepare this order. Try again.", 502, "prepare_failed", root);
  }
  return { url, headers, body };
}

/**
 * Submit a prepared order from the browser to CLOB.
 *
 * Mirrors iOS: Peak signs on the server; the device posts so Polymarket’s
 * geoblock sees the user’s IP, not Railway’s. The body string must not be
 * re-serialized — L2 HMAC covers the exact bytes.
 */
export async function submitPreparedOrder(
  prepared: PreparedOrder
): Promise<Record<string, unknown>> {
  let response: Response;
  try {
    response = await fetch(prepared.url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
        ...prepared.headers,
      },
      body: prepared.body,
    });
  } catch {
    throw new PeakApiError(
      "Couldn’t reach the order book from this network. Try again on an allowed connection, or use the Peak iOS app.",
      0,
      "clob_unreachable",
      {}
    );
  }
  const text = await response.text();
  let json: Record<string, unknown> = {};
  try {
    json = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  } catch {
    json = { error: text };
  }
  if (!response.ok) {
    throw new PeakApiError(
      friendlyApiMessage(json, response.status),
      response.status,
      typeof json.code === "string" ? json.code : null,
      json
    );
  }
  // FAK/FOK can return 200 with success:false / empty fill.
  if (json.success === false) {
    throw new PeakApiError(
      friendlyApiMessage(json, response.status),
      response.status,
      typeof json.code === "string" ? json.code : "no_fill",
      json
    );
  }
  return json;
}

/** What actually happened to an order, as far as CLOB will tell us. */
export type OrderOutcome = {
  /**
   * `filled` — matched in full. `partial` — some of it matched. `resting` — it
   * is on the book, unmatched, and will sit there. `submitted` — accepted, but
   * CLOB did not say enough to classify it.
   */
  kind: "filled" | "partial" | "resting" | "submitted";
  orderId: string | null;
  /** Shares matched, or `null` when it cannot be established with confidence. */
  filledSize: number | null;
  /** Shares asked for. */
  requestedSize: number;
  /** Raw CLOB status, for display when nothing better is known. */
  status: string | null;
};

/**
 * Shares filled, or `null` when it cannot be established with confidence.
 *
 * Ported from iOS `TradingService.normalizedFill`, including the reason it
 * looks paranoid. CLOB returns these as decimal strings, and depending on the
 * endpoint they may be human share counts *or* raw 1e6 base units. Guessing
 * wrong does not crash — it prints a confidently wrong sentence, which is worse
 * than saying nothing. An earlier iOS attempt to rescale turned a 12345-unit
 * response into "0.01 of 50 shares filled": a plausible-looking lie.
 *
 * So anything that does not already read as a share count is reported as
 * unknown, and the UI degrades to "submitted" — vague, but never false.
 */
export function normalizedFill(raw: unknown, requestedShares: number): number | null {
  const value =
    typeof raw === "number"
      ? raw
      : typeof raw === "string" && raw.trim() !== ""
        ? Number(raw)
        : null;
  if (value === null || !Number.isFinite(value) || value < 0) return null;
  if (requestedShares <= 0) return null;
  if (value === 0) return 0;
  // Allow slight over-fill for tick rounding; reject anything beyond it, which
  // is the signal that we are looking at base units rather than shares.
  if (value > requestedShares * 1.05) return null;
  return value;
}

/**
 * Classify a CLOB submit response.
 *
 * Throwing is the caller's job — by the time this runs the request succeeded.
 * This only decides how to describe it, and errs toward the vaguer answer.
 */
export function parseOrderOutcome(
  result: Record<string, unknown>,
  side: "BUY" | "SELL",
  requestedSize: number
): OrderOutcome {
  const orderId =
    (typeof result.orderID === "string" && result.orderID) ||
    (typeof result.id === "string" && result.id) ||
    null;
  const status =
    typeof result.status === "string" && result.status.trim()
      ? result.status.trim()
      : null;

  // A sell makes shares and takes cash; a buy is the reverse.
  const shareLeg = side === "SELL" ? result.makingAmount : result.takingAmount;
  const filledSize = normalizedFill(shareLeg, requestedSize);

  const lower = status?.toLowerCase() ?? "";
  let kind: OrderOutcome["kind"] = "submitted";

  if (filledSize != null && filledSize > 0) {
    // Treat a hair under the request as complete — tick rounding, not a partial.
    kind = filledSize >= requestedSize * 0.995 ? "filled" : "partial";
  } else if (lower === "matched") {
    // Matched, but the size did not survive the confidence check above.
    kind = "filled";
  } else if (lower === "live" || lower === "delayed") {
    kind = "resting";
  } else if (filledSize === 0) {
    kind = "resting";
  }

  return { kind, orderId, filledSize, requestedSize, status };
}

/**
 * True only when the backend predates `/orders/prepare`.
 * Kept narrow on purpose — bare 404 must not silently resend via Railway IP
 * for business failures (those use 4xx + `code`, not a missing route).
 */
export function isMissingPrepareEndpoint(err: unknown): boolean {
  if (!(err instanceof PeakApiError)) return false;
  if (err.status !== 404) return false;
  if (err.code && err.code !== "not_found") return false;
  return true;
}

/** Fallback when `/orders/prepare` is missing on an older backend. */
export async function placeOrderDirect(
  token: string,
  order: Record<string, unknown>
): Promise<Record<string, unknown>> {
  return peakFetch("orders", { method: "POST", token, body: order });
}

function mapSession(root: Record<string, unknown>): TradingSession {
  return {
    eoa: typeof root.eoa === "string" ? root.eoa : typeof root.signer === "string" ? root.signer : "",
    accountWallet:
      typeof root.accountWallet === "string"
        ? root.accountWallet
        : typeof root.safeAddress === "string"
          ? root.safeAddress
          : null,
    safeAddress: typeof root.safeAddress === "string" ? root.safeAddress : null,
    walletTypeName: typeof root.walletTypeName === "string" ? root.walletTypeName : null,
    path: typeof root.path === "string" ? root.path : null,
    ready: root.ready === true,
    syncReady: root.syncReady === true,
    needsDeploy: root.needsDeploy === true,
    builderConfigured: root.builderConfigured === true,
    message: typeof root.message === "string" ? root.message : null,
  };
}

function mapPosition(row: Record<string, unknown>): Position | null {
  const title =
    (typeof row.title === "string" && row.title) ||
    (typeof row.eventTitle === "string" && row.eventTitle) ||
    null;
  if (!title) return null;
  const size = Number(row.size ?? row.amount ?? 0);
  if (!Number.isFinite(size) || size === 0) return null;
  return {
    title,
    outcome: typeof row.outcome === "string" ? row.outcome : "—",
    size,
    avgPrice: numOrNull(row.avgPrice),
    curPrice: numOrNull(row.curPrice ?? row.price),
    cashPnl: numOrNull(row.cashPnl ?? row.pnl),
    eventSlug: typeof row.eventSlug === "string" ? row.eventSlug : null,
    asset:
      (typeof row.asset === "string" && row.asset) ||
      (typeof row.tokenId === "string" && row.tokenId) ||
      (typeof row.tokenID === "string" && row.tokenID) ||
      null,
  };
}

function mapActivity(row: Record<string, unknown>): ActivityItem | null {
  const title = typeof row.title === "string" ? row.title : null;
  if (!title) return null;
  const type = typeof row.type === "string" ? row.type : "ACTIVITY";
  const timestamp = numOrNull(row.timestamp);
  const id = [
    typeof row.transactionHash === "string" ? row.transactionHash : null,
    typeof row.conditionId === "string" ? row.conditionId : null,
    type,
    timestamp != null ? String(timestamp) : null,
    typeof row.outcome === "string" ? row.outcome : null,
  ]
    .filter(Boolean)
    .join("|");
  return {
    id: id || `${title}-${type}-${timestamp ?? 0}`,
    title,
    outcome: typeof row.outcome === "string" ? row.outcome : null,
    type,
    side: typeof row.side === "string" ? row.side : null,
    size: numOrNull(row.size) ?? 0,
    price: numOrNull(row.price) ?? 0,
    usdcSize: numOrNull(row.usdcSize) ?? 0,
    timestamp,
    eventSlug: typeof row.slug === "string" ? row.slug : null,
  };
}

function mapOpenOrder(row: Record<string, unknown>): OpenOrder | null {
  const id =
    (typeof row.id === "string" && row.id) ||
    (typeof row.orderID === "string" && row.orderID) ||
    (typeof row.order_id === "string" && row.order_id) ||
    null;
  if (!id) return null;
  return {
    id,
    tokenID:
      (typeof row.asset_id === "string" && row.asset_id) ||
      (typeof row.tokenID === "string" && row.tokenID) ||
      "",
    market: typeof row.market === "string" ? row.market : null,
    side: String(row.side ?? "BUY").toUpperCase(),
    price: numOrNull(row.price) ?? 0,
    originalSize: numOrNull(row.original_size) ?? numOrNull(row.size) ?? 0,
    sizeMatched: numOrNull(row.size_matched) ?? numOrNull(row.matched) ?? 0,
    status: typeof row.status === "string" ? row.status : null,
  };
}

function numOrNull(value: unknown): number | null {
  const n = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
  return Number.isFinite(n) ? n : null;
}
