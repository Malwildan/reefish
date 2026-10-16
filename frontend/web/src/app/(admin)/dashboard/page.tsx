import { DashboardView } from "@/features/dashboard/components/dashboard-view";

export default async function DashboardPage({ searchParams }: PageProps<"/dashboard">) {
  const q = await searchParams;
  const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
  return <DashboardView grid={one(q.grid)} notice={one(q.notice)} empty={one(q.data) === "kosong"} />;
}
