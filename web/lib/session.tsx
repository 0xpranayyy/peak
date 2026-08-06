"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import { usePrivy, useWallets } from "@privy-io/react-auth";
import {
  setupTrading,
  syncSession,
  type TradingSession,
} from "@/lib/api";
import { fetchGeo, type GeoStatus } from "@/lib/geo";

type PeakSessionValue = {
  ready: boolean;
  authenticated: boolean;
  privyConfigured: boolean;
  eoa: string | null;
  session: TradingSession | null;
  geo: GeoStatus | null;
  syncing: boolean;
  error: string | null;
  login: () => void;
  logout: () => Promise<void>;
  getToken: () => Promise<string | null>;
  refreshSession: () => Promise<void>;
  runSetup: () => Promise<void>;
};

const PeakSessionContext = createContext<PeakSessionValue | null>(null);

const PRIVY_CONFIGURED = Boolean(process.env.NEXT_PUBLIC_PRIVY_APP_ID);

function PeakSessionInner({ children }: { children: React.ReactNode }) {
  const { ready, authenticated, login, logout, getAccessToken, user } = usePrivy();
  const { wallets } = useWallets();
  const [session, setSession] = useState<TradingSession | null>(null);
  const [geo, setGeo] = useState<GeoStatus | null>(null);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const eoa = useMemo(() => {
    const embedded = wallets.find(
      (w) => w.walletClientType === "privy" || w.connectorType === "embedded"
    );
    const any = embedded ?? wallets[0];
    const fromWallet = any?.address?.toLowerCase() ?? null;
    if (fromWallet) return fromWallet;
    const linked = user?.wallet?.address?.toLowerCase() ?? null;
    return linked;
  }, [wallets, user]);

  useEffect(() => {
    let cancelled = false;
    fetchGeo().then((g) => {
      if (!cancelled) setGeo(g);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const refreshSession = useCallback(async () => {
    if (!authenticated || !eoa) {
      setSession(null);
      return;
    }
    setSyncing(true);
    setError(null);
    try {
      const token = await getAccessToken();
      if (!token) throw new Error("Couldn’t get a Privy session token.");
      const next = await syncSession(token, eoa, "new");
      setSession(next);
      if (next.needsDeploy) {
        try {
          const setup = await setupTrading(token);
          setSession(setup);
        } catch (setupErr) {
          // Setup can fail until Builder/Relayer is warm; keep session anyway.
          const message =
            setupErr instanceof Error ? setupErr.message : "Trading setup failed.";
          setError(message);
        }
      }
    } catch (err) {
      setSession(null);
      setError(err instanceof Error ? err.message : "Session sync failed.");
    } finally {
      setSyncing(false);
    }
  }, [authenticated, eoa, getAccessToken]);

  useEffect(() => {
    if (!ready) return;
    if (!authenticated || !eoa) {
      setSession(null);
      return;
    }
    void refreshSession();
  }, [ready, authenticated, eoa, refreshSession]);

  const runSetup = useCallback(async () => {
    const token = await getAccessToken();
    if (!token) throw new Error("Sign in first.");
    setSyncing(true);
    setError(null);
    try {
      const next = await setupTrading(token);
      setSession(next);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Trading setup failed.");
      throw err;
    } finally {
      setSyncing(false);
    }
  }, [getAccessToken]);

  const getToken = useCallback(async () => {
    if (!authenticated) return null;
    return getAccessToken();
  }, [authenticated, getAccessToken]);

  const value: PeakSessionValue = {
    ready,
    authenticated,
    privyConfigured: true,
    eoa,
    session,
    geo,
    syncing,
    error,
    login,
    logout,
    getToken,
    refreshSession,
    runSetup,
  };

  return (
    <PeakSessionContext.Provider value={value}>{children}</PeakSessionContext.Provider>
  );
}

function PeakSessionFallback({ children }: { children: React.ReactNode }) {
  const [geo, setGeo] = useState<GeoStatus | null>(null);
  useEffect(() => {
    fetchGeo().then(setGeo);
  }, []);

  const value: PeakSessionValue = {
    ready: true,
    authenticated: false,
    privyConfigured: false,
    eoa: null,
    session: null,
    geo,
    syncing: false,
    error: null,
    login: () => {
      window.alert(
        "Set NEXT_PUBLIC_PRIVY_APP_ID in web/.env.local to enable sign-in."
      );
    },
    logout: async () => undefined,
    getToken: async () => null,
    refreshSession: async () => undefined,
    runSetup: async () => undefined,
  };

  return (
    <PeakSessionContext.Provider value={value}>{children}</PeakSessionContext.Provider>
  );
}

export function PeakSessionProvider({ children }: { children: React.ReactNode }) {
  if (!PRIVY_CONFIGURED) {
    return <PeakSessionFallback>{children}</PeakSessionFallback>;
  }
  return <PeakSessionInner>{children}</PeakSessionInner>;
}

export function usePeakSession(): PeakSessionValue {
  const ctx = useContext(PeakSessionContext);
  if (!ctx) {
    throw new Error("usePeakSession must be used within PeakSessionProvider");
  }
  return ctx;
}
