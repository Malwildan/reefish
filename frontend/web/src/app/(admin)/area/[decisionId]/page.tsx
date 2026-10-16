import { DecisionDetail } from "@/features/decisions/components/decision-detail";

export default async function DecisionPage({ params, searchParams }: PageProps<"/area/[decisionId]">) {
  const [{ decisionId }, q] = await Promise.all([params, searchParams]);
  const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
  return <DecisionDetail id={decisionId} action={one(q.aksi)} notice={one(q.notice)} />;
}
