import { EditDecision } from "@/features/decisions/components/edit-decision";

export default async function EditDecisionPage({ params }: PageProps<"/area/[decisionId]/edit">) {
  const { decisionId } = await params;
  return <EditDecision id={decisionId} />;
}
