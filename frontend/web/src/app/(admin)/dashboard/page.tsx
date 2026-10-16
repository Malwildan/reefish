import { Suspense } from "react";
import { PageSkeleton } from "@/components/layout/page-skeleton";
import { DashboardView } from "@/features/dashboard/components/dashboard-view";

// Query params are request data; the static shell (layout + skeleton) renders first.
export default function DashboardPage({ searchParams }: PageProps<"/dashboard">) {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Content searchParams={searchParams} />
    </Suspense>
  );
}

async function Content({ searchParams }: Pick<PageProps<"/dashboard">, "searchParams">) {
  const q = await searchParams;
  const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
  const grids = (one(q.grids) ?? "").split(",").map((g) => g.trim()).filter(Boolean).slice(0, 5000);
  return <DashboardView notice={one(q.notice)} grids={grids} />;
}
