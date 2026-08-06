/**
 * Peak trading API client (browser).
 *
 * All authenticated calls go through `/api/peak/*` (Next edge proxy) so we do
 * not depend on Railway `CORS_ORIGINS`. Market data stays on the public edge
 * Worker via `lib/gamma.ts`.
 */

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

export async function peakFetch(
  path: string,
  options: {
    method?: string;
    token?: string | null;
    body?: Record<string, unknown>;
    query?: Record<string, string | number | undefined>;
  } = {}
): Promise<Record<string, unknown>> {
  const url = new URL(`/api/peak/${path.replace(/^\//, "")}`, window.location.origin);
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

  const response = await fetch(url.toString(), {
    method: options.method ?? (options.body ? "POST" : "GET"),
    headers,
    body: options.body ? JSON.stringify(options.body) : undefined,
    cache: "no-store",
  });

  const json = await parseJson(response);
  if (!response.ok) {
    const message =
      (typeof json.error === "string" && json.error) ||
      (typeof json.errorMsg === "string" && json.errorMsg) ||
      `Request failed (${response.status})`;
    throw new PeakApiError(
      message,
      response.status,
      typeof json.code === "string" ? json.code : null,
      json
    );
  }
  return json;
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
  path: "new" | "existing" = "new"
): Promise<TradingSession> {
  const root = await peakFetch("auth/session", {
    method: "POST",
    token,
    body: { eoa, path },
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

export type PreparedOrder = {
  url: string;
  headers: Record<string, string>;
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
 * geoblock sees the user’s IP, not Railway’s.
 */
export async function submitPreparedOrder(
  prepared: PreparedOrder
): Promise<Record<string, unknown>> {
  const response = await fetch(prepared.url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
      ...prepared.headers,
    },
    body: prepared.body,
  });
  const text = await response.text();
  let json: Record<string, unknown> = {};
  try {
    json = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  } catch {
    json = { error: text };
  }
  if (!response.ok) {
    const message =
      (typeof json.error === "string" && json.error) ||
      (typeof json.errorMsg === "string" && json.errorMsg) ||
      `Order rejected (${response.status})`;
    throw new PeakApiError(
      message,
      response.status,
      typeof json.code === "string" ? json.code : null,
      json
    );
  }
  return json;
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
    syncReady: root.syncReady === true || Boolean(root.accountWallet),
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
  };
}

function numOrNull(value: unknown): number | null {
  const n = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
  return Number.isFinite(n) ? n : null;
}
