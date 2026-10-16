import { Suspense } from "react";
import { PageSkeleton } from "@/components/layout/page-skeleton";
import { ViolationMonitor } from "@/features/violations/components/violation-monitor";

export default function ViolationsPage({ searchParams }: PageProps<"/pantau-pelanggaran">) {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Content searchParams={searchParams} />
    </Suspense>
  );
}

async function Content({ searchParams }: Pick<PageProps<"/pantau-pelanggaran">, "searchParams">) {
  const { id } = await searchParams;
  return <ViolationMonitor selectedId={Array.isArray(id) ? id[0] : id} />;
}
