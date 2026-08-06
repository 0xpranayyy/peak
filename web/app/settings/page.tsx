import { SettingsClient } from "@/components/SettingsClient";

export const runtime = "edge";
export const dynamic = "force-dynamic";

export const metadata = {
  title: "Settings",
  robots: { index: false, follow: false },
};

export default function SettingsPage() {
  return (
    <div className="shell">
      <SettingsClient />
    </div>
  );
}
