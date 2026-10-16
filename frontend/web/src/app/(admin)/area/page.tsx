import { Suspense } from "react";
import { PageSkeleton } from "@/components/layout/page-skeleton";
import { AreaView } from "@/features/decisions/components/area-view";

export default function AreaPage({ searchParams }: PageProps<"/area">) {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Content searchParams={searchParams} />
    </Suspense>
  );
}

async function Content({ searchParams }: Pick<PageProps<"/area">, "searchParams">) {
  const { status } = await searchParams;
  const s = Array.isArray(status) ? status[0] : status;
  return <AreaView status={s === "restricted" || s === "rehab" ? s : undefined} />;
}
