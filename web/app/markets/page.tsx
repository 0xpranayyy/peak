import type { Metadata } from "next";
import { MarketsClient } from "@/components/MarketsClient";

export const runtime = "edge";
export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<{ tag?: string; sort?: string; page?: string }>;
};

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const { tag } = await searchParams;
  if (!tag) {
    return {
      title: "Markets",
      description: "Live Polymarket prediction markets with current odds and volume.",
    };
  }
  const label = tag.replace(/-/g, " ");
  return {
    title: `${label} markets`,
    description: `Live ${label} prediction markets with current odds and volume.`,
  };
}

export default async function MarketsPage({ searchParams }: Props) {
  const params = await searchParams;
  return (
    <MarketsClient tag={params.tag} sort={params.sort} page={params.page} />
  );
}
