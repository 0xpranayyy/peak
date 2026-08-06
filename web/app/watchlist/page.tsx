import { WatchlistClient } from "@/components/WatchlistClient";

export const runtime = "edge";
export const dynamic = "force-dynamic";

export const metadata = {
  title: "Watchlist",
  robots: { index: false, follow: false },
};

export default function WatchlistPage() {
  return (
    <div className="shell">
      <WatchlistClient />
    </div>
  );
}
