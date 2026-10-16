import { AreaView } from "@/features/decisions/components/area-view";

export default async function AreaPage({ searchParams }: PageProps<"/area">) {
  const q = await searchParams;
  const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
  return <AreaView focus={one(q.id)} notice={one(q.notice)} />;
}
