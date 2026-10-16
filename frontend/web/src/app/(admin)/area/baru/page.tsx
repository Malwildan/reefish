import { DecisionForm } from "@/features/decisions/components/decision-form";

export default async function NewDecisionPage({ searchParams }: PageProps<"/area/baru">) {
  const { grid } = await searchParams;
  return <DecisionForm grid={Array.isArray(grid) ? grid[0] : grid} />;
}
