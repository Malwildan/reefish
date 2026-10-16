import Image from "next/image";
import { Card } from "@/components/ui/card";
import { LoginForm } from "@/features/auth/components/login-form";

export const metadata = { title: "Masuk · Reefish Admin" };

export default function LoginPage() {
  return (
    <main className="flex min-h-screen">
      <section className="flex w-[480px] shrink-0 flex-col justify-between bg-primary-pressed p-10 text-inverse">
        <div className="flex items-center gap-3">
          <Image src="/reefish-mark-inverse.svg" alt="" width={46} height={40} priority />
          <span className="t-title-m">Reefish</span>
        </div>
        <div className="flex flex-col gap-3">
          <p className="t-caption text-blue-100">ADMIN KAWASAN</p>
          <h1 className="t-heading-m">Kelola kawasan, lindungi terumbu karang.</h1>
          <p className="t-body text-blue-100">Pantau aktivitas per grid dan terbitkan keputusan area untuk nelayan.</p>
        </div>
        <p className="t-body text-blue-100">Sendang Biru–CMC</p>
      </section>
      <div className="flex flex-1 items-center justify-center p-6">
        <Card className="flex w-[420px] flex-col gap-5 p-7">
          <div className="flex flex-col gap-1">
            <h2 className="t-title-l">Masuk</h2>
            <p className="t-body text-ink-2">Khusus akun konservatif (admin kawasan).</p>
          </div>
          <LoginForm />
        </Card>
      </div>
    </main>
  );
}
