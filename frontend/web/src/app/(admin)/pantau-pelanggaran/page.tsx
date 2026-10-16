import { ViolationMonitor } from "@/features/violations/components/violation-monitor";

export default async function ViolationsPage({ searchParams }: PageProps<"/pantau-pelanggaran">) {
  const { id } = await searchParams;
  return <ViolationMonitor selectedId={Array.isArray(id) ? id[0] : id} />;
}
