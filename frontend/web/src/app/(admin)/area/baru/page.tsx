import { Suspense } from "react";
import { PageSkeleton } from "@/components/layout/page-skeleton";
import { ZoneForm } from "@/features/decisions/components/zone-form";

export default function NewZonePage({ searchParams }: PageProps<"/area/baru">) {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Content searchParams={searchParams} />
    </Suspense>
  );
}

async function Content({ searchParams }: Pick<PageProps<"/area/baru">, "searchParams">) {
  const { grids } = await searchParams;
  const raw = Array.isArray(grids) ? grids.join(",") : (grids ?? "");
  // de-duplicated, at most 5000 like the RPC
  const list = [...new Set(raw.split(",").map((g) => g.trim()).filter(Boolean))].slice(0, 5000);
  return <ZoneForm grids={list} />;
}
