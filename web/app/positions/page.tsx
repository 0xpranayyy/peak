import { PositionsClient } from "@/components/PositionsClient";

export const runtime = "edge";
export const dynamic = "force-dynamic";

export const metadata = {
  title: "Positions",
  robots: { index: false, follow: false },
};

export default function PositionsPage() {
  return (
    <div className="shell detail">
      <PositionsClient />
    </div>
  );
}
