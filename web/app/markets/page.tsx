import type { Metadata } from "next";
import { MarketsClient } from "@/components/MarketsClient";
import { categoryFromSlug } from "@/lib/categories";

export const runtime = "edge";
export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<{ tag?: string; sort?: string }>;
};

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const { tag } = await searchParams;
  const match = categoryFromSlug(tag);

  if (!match) {
    return {
      title: "Markets",
      description: "Live Polymarket prediction markets with current odds and volume.",
    };
  }

  // Titled from the taxonomy, not the raw slug: Gamma's slugs are historical
  // and would surface as "pop culture markets" or "football markets" for NFL.
  const label = match.child
    ? `${match.child.label} — ${match.parent.label}`
    : match.parent.label;
  const subject = match.child?.label ?? match.parent.label;

  return {
    title: `${label} markets`,
    description: `Live ${subject} prediction markets with current odds and volume.`,
  };
}

export default async function MarketsPage({ searchParams }: Props) {
  const params = await searchParams;
  return <MarketsClient tag={params.tag} sort={params.sort} />;
}
