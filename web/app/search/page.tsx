import type { Metadata } from "next";
import { SearchClient } from "@/components/SearchClient";

export const runtime = "edge";

type Props = { searchParams: Promise<{ q?: string }> };

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const { q } = await searchParams;
  return {
    title: q ? `“${q}”` : "Search",
    robots: { index: false, follow: true },
  };
}

export default async function SearchPage({ searchParams }: Props) {
  const { q } = await searchParams;
  return <SearchClient query={q?.trim() ?? ""} />;
}
