import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import type { ApiError } from "../types";

export function Skeleton({ h = 120 }: { h?: number }) {
  return <div className="animate-pulse rounded-[20px] bg-surface" style={{ height: h }} aria-hidden />;
}

export function QueryError({ error, retry }: { error: ApiError; retry?: () => void }) {
  return (
    <Card className="flex flex-col gap-3" role="alert">
      <p className="t-label text-error">{error.code === "ZONE_NOT_FOUND" ? "Zona tidak ditemukan" : "Data gagal dimuat"}</p>
      <p className="t-body text-ink-2">{error.message}</p>
      {retry && error.code !== "ZONE_NOT_FOUND" && (
        <Button variant="secondary" onClick={retry} className="w-[180px]">
          Coba lagi
        </Button>
      )}
    </Card>
  );
}
