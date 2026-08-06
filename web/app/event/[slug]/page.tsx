import type { Metadata } from "next";
import { EventClient } from "@/components/EventClient";

export const runtime = "edge";
export const dynamic = "force-dynamic";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const label = slug.replace(/-/g, " ");
  return {
    title: label || "Market",
    description: "Live odds and trade ticket on Peak.",
  };
}

export default async function EventPage({ params }: Props) {
  const { slug } = await params;
  return <EventClient slug={slug} />;
}
