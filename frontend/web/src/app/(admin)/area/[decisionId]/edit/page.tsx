import { Suspense } from "react";
import { PageSkeleton } from "@/components/layout/page-skeleton";
import { EditDecision } from "@/features/decisions/components/edit-decision";

export default function EditDecisionPage({ params }: PageProps<"/area/[decisionId]/edit">) {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Content params={params} />
    </Suspense>
  );
}

async function Content({ params }: Pick<PageProps<"/area/[decisionId]/edit">, "params">) {
  const { decisionId } = await params;
  return <EditDecision id={decisionId} />;
}
