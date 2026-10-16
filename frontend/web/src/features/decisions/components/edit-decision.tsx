"use client";

import { ButtonLink } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { isExpired } from "../services/store";
import { DecisionForm } from "./decision-form";
import { useDecision } from "./use-decision";

export function EditDecision({ id }: { id: string }) {
  const d = useDecision(id);
  if (!d) return <NotFound />;
  if (d.status === "dicabut" || isExpired(d)) {
    return (
      <Card className="flex max-w-[560px] flex-col gap-4">
        <h1 className="t-title-m">Keputusan tidak bisa diedit</h1>
        <p className="t-body text-ink-2">Keputusan yang sudah dicabut atau berakhir hanya bisa dilihat.</p>
        <ButtonLink href={`/area/${d.id}`} variant="secondary">
          Lihat keputusan
        </ButtonLink>
      </Card>
    );
  }
  // key: reset the form when the stored decision changes underneath
  return <DecisionForm key={d.id} existing={d} />;
}

export function NotFound() {
  return (
    <Card className="flex max-w-[560px] flex-col gap-4">
      <h1 className="t-title-m">Keputusan tidak ditemukan</h1>
      <p className="t-body text-ink-2">Keputusan mungkin sudah dihapus.</p>
      <ButtonLink href="/area" variant="secondary">
        Kembali ke Area
      </ButtonLink>
    </Card>
  );
}
