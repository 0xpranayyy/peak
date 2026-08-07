import type { Metadata } from "next";
import { EventClient } from "@/components/EventClient";

export const runtime = "edge";
export const dynamic = "force-dynamic";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  // Derived from the slug rather than fetched: metadata runs before the client
  // load, and paying for a Gamma round-trip on every crawl just to title the tab
  // is not worth it. Gamma appends a numeric id to disambiguate reused slugs
  // ("fed-decision-in-september-762") — that id means nothing to a reader.
  const label = slug
    .replace(/-\d+$/, "")
    .replace(/-/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
  return {
    title: label || "Market",
    description: "Live odds and trade ticket on Peak.",
  };
}

export default async function EventPage({ params }: Props) {
  const { slug } = await params;
  return <EventClient slug={slug} />;
}
