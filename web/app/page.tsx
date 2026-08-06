import { redirect } from "next/navigation";

export const runtime = "edge";

/** Exchange home is Markets — marketing stays on peakapp.site. */
export default function HomePage() {
  redirect("/markets");
}
