import { redirect } from "next/navigation";

export const runtime = "edge";

/** Legacy path — Positions is the canonical route. */
export default function PortfolioRedirect() {
  redirect("/positions");
}
