import { Sidebar } from "@/components/layout/sidebar";

export default function AdminLayout({ children }: LayoutProps<"/">) {
  return (
    <div className="flex min-h-screen min-w-[1200px] bg-canvas">
      <Sidebar region="Sendang Biru–CMC" />
      <main className="flex min-w-0 flex-1 flex-col gap-4 pt-[34px] pr-6 pb-10 pl-[21px]">{children}</main>
    </div>
  );
}
