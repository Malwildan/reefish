"use client";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

export default function AdminError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <Card className="flex max-w-[560px] flex-col gap-4" role="alert">
      <h1 className="t-title-m">Halaman gagal dimuat</h1>
      <p className="t-body text-ink-2">{error.message || "Terjadi kesalahan. Coba lagi."}</p>
      <Button onClick={reset}>Coba lagi</Button>
    </Card>
  );
}
