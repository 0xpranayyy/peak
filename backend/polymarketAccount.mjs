/**
 * Resolve Polymarket account wallet + type for a signer EOA.
 * @see https://docs.polymarket.com/trading/deposit-wallets
 * WalletType: 0=EOA, 1=POLY_PROXY, 2=GNOSIS_SAFE, 3=DEPOSIT_WALLET
 */

const GAMMA = "https://gamma-api.polymarket.com";
const DATA = "https://data-api.polymarket.com";

/** @typedef {'new' | 'existing'} TradingPath */
/** @typedef {'EOA' | 'POLY_PROXY' | 'GNOSIS_SAFE' | 'DEPOSIT_WALLET' | 'UNKNOWN'} WalletTypeName */

const WALLET_TYPE = {
  EOA: 0,
  POLY_PROXY: 1,
  GNOSIS_SAFE: 2,
  DEPOSIT_WALLET: 3,
};

/**
 * @param {string} address
 * @returns {Promise<{ proxyWallet: string | null, profile: object | null }>}
 */
export async function fetchPublicProfile(address) {
  const url = `${GAMMA}/public-profile?address=${encodeURIComponent(address)}`;
  const r = await fetch(url);
  if (r.status === 404) {
    return { proxyWallet: null, profile: null };
  }
  if (!r.ok) {
    throw new Error(`Gamma public-profile → ${r.status}`);
  }
  const profile = await r.json();
  const proxy =
    typeof profile?.proxyWallet === "string" && /^0x[a-fA-F0-9]{40}$/i.test(profile.proxyWallet)
      ? profile.proxyWallet
      : null;
  return { proxyWallet: proxy, profile };
}

/**
 * Heuristic: if Data API has meaningful positions/value for an address, treat it as active book.
 * @param {string} address
 */
async function hasBookActivity(address) {
  try {
    const [positions, value] = await Promise.all([
      fetch(`${DATA}/positions?user=${address}&sizeThreshold=0`).then((r) => (r.ok ? r.json() : [])),
      fetch(`${DATA}/value?user=${address}`).then((r) => (r.ok ? r.json() : null)),
    ]);
    const posCount = Array.isArray(positions) ? positions.length : 0;
    const v = Number(value?.value ?? value?.[0]?.value ?? 0);
    return posCount > 0 || v > 0;
  } catch {
    return false;
  }
}

/**
 * Infer wallet type when SDK SecureClient isn't available yet.
 * Existing Polymarket social → usually Proxy; MetaMask → Safe; new Builder path → Deposit.
 * @param {{ path: TradingPath, signer: string, accountWallet: string | null, profileFound: boolean }} args
 * @returns {{ walletType: number, walletTypeName: WalletTypeName }}
 */
export function inferWalletType({ path, signer, accountWallet, profileFound }) {
  if (!accountWallet || accountWallet.toLowerCase() === signer.toLowerCase()) {
    return { walletType: WALLET_TYPE.EOA, walletTypeName: "EOA" };
  }
  if (path === "new") {
    return { walletType: WALLET_TYPE.DEPOSIT_WALLET, walletTypeName: "DEPOSIT_WALLET" };
  }
  // Existing account with a distinct proxyWallet from Gamma — historically Proxy or Safe.
  // Prefer POLY_PROXY when profile exists (Magic/Google era); Safe when user imported MetaMask key.
  // Without on-chain detection, mark UNKNOWN subtype as POLY_PROXY if profile-linked, else GNOSIS_SAFE.
  if (profileFound) {
    return { walletType: WALLET_TYPE.POLY_PROXY, walletTypeName: "POLY_PROXY" };
  }
  return { walletType: WALLET_TYPE.GNOSIS_SAFE, walletTypeName: "GNOSIS_SAFE" };
}

/**
 * Resolve signer → account wallet for Peak session.
 * @param {{ signer: string, path?: TradingPath, accountWalletHint?: string | null }} opts
 */
export async function resolvePolymarketAccount({ signer, path = "new", accountWalletHint = null }) {
  const normalizedSigner = signer.trim();
  let accountWallet = accountWalletHint?.trim() || null;
  let profile = null;
  let profileFound = false;

  // 1) Explicit hint (user pasted Polymarket profile address)
  if (accountWallet && /^0x[a-fA-F0-9]{40}$/.test(accountWallet)) {
    profileFound = true;
    try {
      const hinted = await fetchPublicProfile(accountWallet);
      profile = hinted.profile;
    } catch (e) {
      console.warn("public-profile (hint) lookup failed:", e?.message ?? e);
    }
  } else {
    // 2) Gamma public profile by signer
    try {
      const result = await fetchPublicProfile(normalizedSigner);
      profile = result.profile;
      if (result.proxyWallet) {
        accountWallet = result.proxyWallet;
        profileFound = true;
      }
    } catch (e) {
      console.warn("public-profile lookup failed:", e?.message ?? e);
    }
  }

  // 3) New trader with no existing book → account wallet TBD until Builder deploy
  if (path === "new" && !accountWallet) {
    const { walletType, walletTypeName } = inferWalletType({
      path,
      signer: normalizedSigner,
      accountWallet: null,
      profileFound: false,
    });
    return {
      signer: normalizedSigner,
      accountWallet: null,
      walletType,
      walletTypeName,
      path,
      profile,
      needsDeploy: true,
      syncReady: false,
      message:
        "New account. A deposit wallet will be created when Builder credentials are configured.",
    };
  }

  // 4) Existing path but no proxy found — signer may still hold EOA book, or need manual address
  if (path === "existing" && !accountWallet) {
    const eoaHasBook = await hasBookActivity(normalizedSigner);
    if (eoaHasBook) {
      accountWallet = normalizedSigner;
    } else {
      return {
        signer: normalizedSigner,
        accountWallet: null,
        walletType: WALLET_TYPE.EOA,
        walletTypeName: "EOA",
        path,
        profile,
        needsDeploy: false,
        syncReady: false,
        message:
          "We couldn’t find a Polymarket account for this wallet. Import the wallet you use on Polymarket, or enter your profile address.",
      };
    }
  }

  const { walletType, walletTypeName } = inferWalletType({
    path,
    signer: normalizedSigner,
    accountWallet,
    profileFound,
  });

  return {
    signer: normalizedSigner,
    accountWallet,
    walletType,
    walletTypeName,
    path,
    profile: profile
      ? {
          name: profile.name ?? null,
          pseudonym: profile.pseudonym ?? null,
          proxyWallet: profile.proxyWallet ?? null,
          profileImage: profile.profileImage ?? null,
          displayUsernamePublic: profile.displayUsernamePublic ?? null,
          verifiedBadge: profile.verifiedBadge ?? null,
          bio: profile.bio ?? null,
          xUsername: profile.xUsername ?? null,
        }
      : null,
    needsDeploy: path === "new" && !accountWallet,
    syncReady: Boolean(accountWallet),
    message: accountWallet
      ? "Connected to your Polymarket account."
      : "Account wallet not resolved yet.",
  };
}

export { WALLET_TYPE };
