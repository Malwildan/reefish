import { Suspense } from "react";
import { PageSkeleton } from "@/components/layout/page-skeleton";
import { DecisionDetail } from "@/features/decisions/components/decision-detail";

export default function DecisionPage(props: PageProps<"/area/[decisionId]">) {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Content {...props} />
    </Suspense>
  );
}

async function Content({ params, searchParams }: PageProps<"/area/[decisionId]">) {
  const [{ decisionId }, q] = await Promise.all([params, searchParams]);
  const notice = Array.isArray(q.notice) ? q.notice[0] : q.notice;
  return <DecisionDetail id={decisionId} notice={notice} />;
}
