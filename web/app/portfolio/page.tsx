import { PortfolioClient } from "@/components/PortfolioClient";

export const runtime = "edge";
export const dynamic = "force-dynamic";

export const metadata = {
  title: "Portfolio",
  robots: { index: false, follow: false },
};

export default function PortfolioPage() {
  return (
    <div className="shell detail">
      <PortfolioClient />
    </div>
  );
}
