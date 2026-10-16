import { Suspense } from "react";
import { PageSkeleton } from "@/components/layout/page-skeleton";
import { ViolationMonitor } from "@/features/violations/components/violation-monitor";
import { PageHeader } from "@/components/layout/page-header";
import { Notice } from "@/components/ui/card";

export default function ViolationsPage({ searchParams }: PageProps<"/pantau-pelanggaran">) {
  if (process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.NODE_ENV === "production") {
    return (
      <>
        <PageHeader title="Pantau pelanggaran" subtitle="Pemantauan aktivitas kawasan" />
        <Notice tone="info">Pemantauan jejak nelayan dan pengiriman peringatan belum terhubung. Kelola pembatasan kawasan melalui Dashboard dan Area.</Notice>
      </>
    );
  }
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
