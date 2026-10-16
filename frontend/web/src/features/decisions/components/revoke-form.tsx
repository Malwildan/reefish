"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card, Notice } from "@/components/ui/card";
import { Field, InfoBox, TextAreaField } from "@/components/ui/field";
import { HeatmapMap } from "@/features/geo/components/heatmap-map";
import { HEATMAP, heatCell } from "@/features/geo/mock-heatmap";
import { fmtDate, KIND_TITLE } from "../format";
import { validateRevoke, type RevokeInput } from "../schemas";
import { saveDecision, today, type Decision } from "../services/store";

export function RevokeForm({ decision: d }: { decision: Decision }) {
  const router = useRouter();
  const published = d.history.find((h) => h.text.startsWith("Terbit"))?.at ?? d.start;
  const [v, setV] = useState<RevokeInput>({ date: today(), reason: "", basis: "", meetingDate: "", summary: "" });
  const [errors, setErrors] = useState<Partial<Record<keyof RevokeInput, string>>>({});
  const set = (k: keyof RevokeInput, val: string) => setV((p) => ({ ...p, [k]: val }));
  const cs = d.cells.map(heatCell).filter((c) => !!c);

  function submit() {
    const errs = validateRevoke(v, published);
    setErrors(errs);
    if (Object.keys(errs).length) return;
    saveDecision({
      ...d,
      status: "dicabut",
      revoke: v,
      history: [...d.history, { at: today(), text: `Dicabut · ${v.reason}` }],
    });
    router.push(`/area/${d.id}?notice=dicabut`);
  }

  return (
    <>
      <PageHeader title="Cabut keputusan kawasan" subtitle={`${d.code} · alasan pencabutan wajib dicatat`} />
      <div className="grid grid-cols-[minmax(0,1fr)_372px] items-start gap-5">
        <Card className="flex flex-col gap-4 p-0">
          <HeatmapMap cells={HEATMAP} closed={d.cells} selected={d.cells} fitSelected title={`Bukti map · grid ${d.code}`} subtitle="Geser untuk melihat area lain" height={570} />
          <div className="flex flex-col gap-[6px] px-5 pb-5">
            <p className="t-label">
              {d.code} · {Math.max(0, ...cs.map((c) => c.fishers))} nelayan unik
            </p>
            <p className="t-body text-ink-2">
              {cs.reduce((s, c) => s + c.trips, 0)} trip · {cs.reduce((s, c) => s + c.hours, 0)} jam · 4 minggu tertutup
            </p>
          </div>
        </Card>
        <Card className="flex flex-col gap-3">
          <h2 className="t-title-m">Detail keputusan</h2>
          <form
            noValidate
            className="flex flex-col gap-3"
            onSubmit={(e) => {
              e.preventDefault();
              submit();
            }}
          >
            <div className="grid grid-cols-2 gap-3">
              <InfoBox label="Tindakan">Cabut {KIND_TITLE[d.kind].toLowerCase()}</InfoBox>
              <InfoBox label="Grid">{d.code}</InfoBox>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <InfoBox label="Diterbitkan">{fmtDate(published)}</InfoBox>
              <Field id="rv-date" label="Pencabutan efektif" type="date" value={v.date} onChange={(e) => set("date", e.target.value)} error={errors.date} />
            </div>
            <TextAreaField id="rv-reason" label="Alasan pencabutan" value={v.reason} onChange={(e) => set("reason", e.target.value)} error={errors.reason} placeholder="Evaluasi kawasan menunjukkan kondisi membaik." />
            <TextAreaField id="rv-basis" label="Dasar evaluasi" value={v.basis} onChange={(e) => set("basis", e.target.value)} placeholder="Kajian kondisi karang dan area rehab ditinjau." />
            <Field id="rv-meeting" label="Tanggal rapat" type="date" value={v.meetingDate} onChange={(e) => set("meetingDate", e.target.value)} error={errors.meetingDate} />
            <TextAreaField id="rv-summary" label="Ringkasan kesepakatan" value={v.summary} onChange={(e) => set("summary", e.target.value)} placeholder="Rapat menyetujui pencabutan setelah evaluasi" />
            <p className="t-body text-ink-2">Bukti map periode ini dilampirkan otomatis.</p>
            <p className="t-label">Jika dicabut:</p>
            <p className="t-body text-ink-2">Status {d.code} diperbarui untuk semua nelayan.</p>
            <p className="t-body text-ink-2">Paket berikutnya dihitung ulang dari data terbaru.</p>
            <Notice>Batas area dan alasan keputusan tersimpan bersama bukti map.</Notice>
            <div className="flex flex-col gap-3 pt-2">
              <ButtonLink href={`/area/${d.id}`} variant="secondary">
                Kembali ke keputusan
              </ButtonLink>
              <Button type="submit">Cabut keputusan</Button>
            </div>
          </form>
        </Card>
      </div>
    </>
  );
}
