"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card, Notice } from "@/components/ui/card";
import { Field, SelectField, TextAreaField } from "@/components/ui/field";
import { HeatmapMap } from "@/features/geo/components/heatmap-map";
import { HEATMAP, heatCell } from "@/features/geo/mock-heatmap";
import { KIND_LABEL } from "../format";
import { validateDecision, type DecisionInput, type Errors } from "../schemas";
import { saveDecision, today, useDecisions, type Decision } from "../services/store";

function addDays(iso: string, n: number) {
  const d = new Date(iso + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export function DecisionForm({ existing, grid }: { existing?: Decision; grid?: string }) {
  const router = useRouter();
  const all = useDecisions();
  const [v, setV] = useState<DecisionInput>(() =>
    existing
      ? { ...existing }
      : {
          code: `SB-${String.fromCharCode(65 + (all.length % 26))}${all.length + 1}`,
          kind: "tutup",
          cells: grid && heatCell(grid) ? [grid] : [],
          start: today(),
          end: addDays(today(), 14),
          reason: "",
          reopenCriteria: "",
          meetingDate: "",
          meetingSummary: "",
        },
  );
  const [errors, setErrors] = useState<Errors>({});
  const set = <K extends keyof DecisionInput>(k: K, val: DecisionInput[K]) => setV((p) => ({ ...p, [k]: val }));

  // Cells already held by another active decision cannot be taken (one active zone per grid).
  const taken = useMemo(
    () => new Set(all.filter((d) => d.id !== existing?.id && d.status !== "dicabut").flatMap((d) => d.cells)),
    [all, existing],
  );
  const stats = useMemo(() => {
    const cs = v.cells.map(heatCell).filter((c) => !!c);
    return {
      fishers: Math.max(0, ...cs.map((c) => c.fishers)),
      trips: cs.reduce((s, c) => s + c.trips, 0),
      hours: cs.reduce((s, c) => s + c.hours, 0),
    };
  }, [v.cells]);

  function toggle(id: string) {
    if (taken.has(id)) return setErrors((e) => ({ ...e, cells: `${id} sudah masuk keputusan lain.` }));
    setErrors((e) => ({ ...e, cells: undefined }));
    set("cells", v.cells.includes(id) ? v.cells.filter((c) => c !== id) : [...v.cells, id]);
  }

  function submit(publish: boolean) {
    const errs = validateDecision(v, publish);
    setErrors(errs);
    if (Object.keys(errs).length) return;
    const now = today();
    const base: Decision = existing ?? { ...v, id: crypto.randomUUID(), status: "draf", history: [] };
    const wasDraft = base.status === "draf";
    const status = publish ? "terbit" : base.status;
    const history = [...base.history];
    if (!existing) history.push({ at: now, text: "Draf dibuat · catatan rapat tersimpan" });
    else history.push({ at: now, text: "Perubahan disimpan · tercatat pada audit keputusan" });
    if (publish && wasDraft) history.push({ at: now, text: "Terbit · tercatat pada audit keputusan" });
    saveDecision({ ...base, ...v, quotaKg: v.kind === "kuota" ? Number(v.quotaKg) : undefined, status, history });
    router.push(`/dashboard?notice=${existing ? "disimpan" : publish ? "dibuat" : "draf"}`);
  }

  const isPublished = existing?.status === "terbit";

  return (
    <>
      <PageHeader
        title={existing ? "Edit keputusan" : "Buat keputusan area"}
        subtitle={
          existing
            ? `${existing.code} · perubahan tercatat pada riwayat keputusan`
            : `Draf keputusan untuk grid ${v.code} · hanya admin kawasan`
        }
      />
      <div className="grid grid-cols-[minmax(0,1fr)_372px] items-start gap-5">
        <Card className="flex flex-col gap-4 p-0">
          <HeatmapMap
            cells={HEATMAP}
            closed={[...taken]}
            selected={v.cells}
            fitSelected={v.cells.length > 0}
            onCellClick={toggle}
            title={`Bukti map · grid ${v.code}`}
            subtitle="Klik grid untuk memilih area"
            height={570}
          />
          <div className="flex flex-col gap-[6px] px-5 pb-5">
            <p className="t-label">
              {v.code} · {v.cells.length} grid · {stats.fishers} nelayan unik
            </p>
            <p className="t-body text-ink-2">
              {stats.trips} trip · {stats.hours} jam · 4 minggu tertutup
            </p>
            {errors.cells && (
              <p className="t-caption text-error" role="alert">
                {errors.cells}
              </p>
            )}
          </div>
        </Card>

        <Card className="flex flex-col gap-3">
          <h2 className="t-title-m">Detail keputusan</h2>
          <form
            className="flex flex-col gap-3"
            noValidate
            onSubmit={(e) => {
              e.preventDefault();
              submit(true);
            }}
          >
            <div className="grid grid-cols-2 gap-3">
              <SelectField
                id="kind"
                label="Jenis"
                value={v.kind}
                onChange={(e) => set("kind", e.target.value as DecisionInput["kind"])}
              >
                <option value="tutup">{KIND_LABEL.tutup}</option>
                <option value="kuota">{KIND_LABEL.kuota}</option>
              </SelectField>
              <Field id="code" label="Grid" value={v.code} onChange={(e) => set("code", e.target.value)} error={errors.code} />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <Field id="start" label="Mulai" type="date" value={v.start} onChange={(e) => set("start", e.target.value)} error={errors.start} />
              <Field id="end" label="Selesai" type="date" value={v.end} onChange={(e) => set("end", e.target.value)} error={errors.end} />
            </div>
            {v.kind === "kuota" && (
              <Field
                id="quota"
                label="Kuota tangkap (kg/bulan)"
                type="number"
                min={1}
                inputMode="numeric"
                value={v.quotaKg ?? ""}
                onChange={(e) => set("quotaKg", e.target.value === "" ? undefined : Number(e.target.value))}
                error={errors.quotaKg}
              />
            )}
            <TextAreaField id="reason" label="Alasan" value={v.reason} onChange={(e) => set("reason", e.target.value)} error={errors.reason} placeholder="Aktivitas tercatat naik dekat zona rehab." />
            <TextAreaField id="reopen" label="Kriteria buka kembali" value={v.reopenCriteria} onChange={(e) => set("reopenCriteria", e.target.value)} placeholder="Evaluasi kawasan dan kondisi karang membaik." />
            <Field id="meeting" label="Tanggal rapat" type="date" value={v.meetingDate} onChange={(e) => set("meetingDate", e.target.value)} error={errors.meetingDate} />
            <TextAreaField id="summary" label="Ringkasan kesepakatan" value={v.meetingSummary} onChange={(e) => set("meetingSummary", e.target.value)} placeholder="Rapat menyepakati penutupan sementara" />

            <p className="t-body text-ink-2">Bukti map periode ini dilampirkan otomatis.</p>
            <p className="t-label">Jika diterbitkan:</p>
            <p className="t-body text-ink-2">
              {stats.fishers + 2} nelayan punya {v.code} sebagai spot kebiasaan.
            </p>
            <p className="t-body text-ink-2">{stats.trips} trip tercatat dalam 4 minggu terakhir.</p>
            <Notice>Batas area dan alasan keputusan tersimpan bersama bukti map.</Notice>

            <div className="flex flex-col gap-3 pt-2">
              {isPublished ? (
                <>
                  <Button type="submit">Simpan perubahan</Button>
                  <ButtonLink href={`/area/${existing.id}`} variant="secondary">
                    Batal
                  </ButtonLink>
                </>
              ) : (
                <>
                  <div className="flex gap-[10px]">
                    <Button variant="warm" className="w-[90px]" onClick={() => router.back()}>
                      Batal
                    </Button>
                    <Button variant="secondary" className="flex-1" onClick={() => submit(false)}>
                      Simpan draf
                    </Button>
                  </div>
                  <Button type="submit">Terbitkan keputusan</Button>
                </>
              )}
            </div>
          </form>
        </Card>
      </div>
    </>
  );
}
