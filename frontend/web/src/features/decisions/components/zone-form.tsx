"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card, Notice } from "@/components/ui/card";
import { Field, TextAreaField } from "@/components/ui/field";
import { HeatmapMap } from "@/features/geo/components/heatmap-map";
import { HEATMAP } from "@/features/geo/mock-heatmap";
import { fromDateInput, STATUS_LABEL, toDateInput } from "../format";
import { useZoneQuery } from "../hooks/use-zones";
import { validateCreate, type FieldErrors } from "../schemas";
import { createZone, listZones, previewZone } from "../services/zones";
import { ApiError, type CreateZoneInput, type ZoneStatus } from "../types";
import { Skeleton, QueryError } from "./query-state";
import { AggregatePanel, emptyRules, RulesFields, rulesFromDraft, StatusChoice, StatusOverview, type RulesDraft } from "./zone-parts";

export function ZoneForm({ grids }: { grids: string[] }) {
  const router = useRouter();
  const key = grids.join(",");
  const preview = useZoneQuery(`preview:${key}`, () => previewZone(grids));
  const zones = useZoneQuery("zones-all", () => listZones({ includeArchived: true }));

  const [name, setName] = useState("");
  const [status, setStatus] = useState<ZoneStatus | null>(null);
  const [rules, setRules] = useState<RulesDraft>(emptyRules);
  const [from, setFrom] = useState(() => toDateInput(new Date().toISOString()));
  const [until, setUntil] = useState("");
  const [reason, setReason] = useState("");
  const [note, setNote] = useState("");
  const [errors, setErrors] = useState<FieldErrors>({});
  const [banner, setBanner] = useState("");
  const [busy, setBusy] = useState(false);

  if (!grids.length) {
    return (
      <>
        <PageHeader title="Pendataan zona" subtitle="Belum ada grid yang dipilih" />
        <Card className="flex max-w-[560px] flex-col gap-4">
          <p className="t-body text-ink-2">Pilih grid di peta dashboard dulu, lalu tekan Buat keputusan.</p>
          <ButtonLink href="/dashboard">Pilih grid di dashboard</ButtonLink>
        </Card>
      </>
    );
  }

  const p = preview.data;
  const usable = p ? grids.filter((g) => !p.invalid_grid_ids.includes(g) && !p.conflicts.some((c) => c.grid_id === g)) : grids;
  const dropUnusable = () => router.replace(`/area/baru?grids=${usable.join(",")}`);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBanner("");
    const input: CreateZoneInput = {
      name,
      status: status ?? "rehab",
      grid_ids: usable,
      rules: status === "restricted" ? rulesFromDraft(rules) : null,
      effective_from: fromDateInput(from),
      effective_until: fromDateInput(until),
      reason,
      note: note || null,
    };
    const errs: FieldErrors = { ...validateCreate(input), ...(status ? {} : { status: "Pilih status zona." }) };
    setErrors(errs);
    if (Object.keys(errs).length) return setBanner("Periksa kembali isian yang ditandai.");
    setBusy(true);
    try {
      const z = await createZone(input);
      router.push(`/area/${z.id}?notice=dibuat`);
    } catch (err) {
      setBusy(false);
      if (!(err instanceof ApiError)) return setBanner("Gagal menyimpan. Coba lagi.");
      if (err.code === "VALIDATION_ERROR") setErrors((err.details?.fields as FieldErrors) ?? {});
      if (err.code === "RULES_REQUIRED") setErrors({ rules: err.message });
      if (err.code === "ZONE_NAME_TAKEN") setErrors({ name: err.message });
      setBanner(err.code === "GRID_CONFLICT" ? `${err.message} Muat ulang untuk melihat grid yang bentrok.` : err.message);
    }
  }

  return (
    <>
      <PageHeader title="Pendataan zona" subtitle={`${grids.length} grid dipilih dari dashboard · status normal tidak perlu didata`} />
      {zones.data && <StatusOverview zones={zones.data} />}

      <div className="grid grid-cols-[minmax(0,1fr)_420px] items-start gap-5">
        <div className="flex min-w-0 flex-col gap-5">
          <HeatmapMap
            cells={HEATMAP}
            selected={usable}
            restricted={p?.conflicts.filter((c) => c.zone_status === "restricted").map((c) => c.grid_id) ?? []}
            rehab={p?.conflicts.filter((c) => c.zone_status === "rehab").map((c) => c.grid_id) ?? []}
            fitSelected
            title="Grid zona"
            subtitle={`${usable.length} grid`}
            height={360}
          />
          {preview.error ? (
            <QueryError error={preview.error} retry={preview.retry} />
          ) : !p ? (
            <Skeleton h={320} />
          ) : (
            <>
              {(p.conflicts.length > 0 || p.invalid_grid_ids.length > 0) && (
                <Notice tone="error" className="flex flex-col gap-2">
                  {p.conflicts.length > 0 && (
                    <span>
                      {p.conflicts.length} grid sudah masuk zona aktif:{" "}
                      {p.conflicts.map((c) => `${c.grid_id} (${STATUS_LABEL[c.zone_status]} "${c.zone_name}")`).join(", ")}.
                    </span>
                  )}
                  {p.invalid_grid_ids.length > 0 && <span>Grid tidak dikenal: {p.invalid_grid_ids.join(", ")}.</span>}
                  {usable.length > 0 ? (
                    <Button variant="secondary" className="w-fit" onClick={dropUnusable}>
                      Lanjutkan tanpa grid tersebut
                    </Button>
                  ) : (
                    <ButtonLink href="/dashboard" variant="secondary" className="w-fit">
                      Pilih ulang grid
                    </ButtonLink>
                  )}
                </Notice>
              )}
              <AggregatePanel a={p.aggregate} title="Agregat grid terpilih" />
            </>
          )}
        </div>

        <Card className="flex flex-col gap-4">
          <h2 className="t-title-m">Data keputusan</h2>
          <form noValidate onSubmit={submit} className="flex flex-col gap-4">
            <Field id="z-name" label="Nama zona" value={name} onChange={(e) => setName(e.target.value)} error={errors.name} placeholder="Karang Timur Sempu" />
            <StatusChoice value={status} onChange={setStatus} error={errors.status} />
            {status === "restricted" && <RulesFields value={rules} onChange={setRules} errors={errors} capacity={p?.aggregate} />}
            {status === "rehab" && (
              <Notice tone="error">Zero tolerance: {usable.length} grid dinonaktifkan. Nelayan tidak bisa memilih atau mencatat tangkapan di grid ini.</Notice>
            )}
            <div className="grid grid-cols-2 gap-3">
              <Field id="z-from" label="Berlaku mulai" type="date" value={from} onChange={(e) => setFrom(e.target.value)} error={errors.effective_from} />
              <Field id="z-until" label="Berakhir (opsional)" type="date" value={until} onChange={(e) => setUntil(e.target.value)} error={errors.effective_until} />
            </div>
            <TextAreaField id="z-reason" label="Alasan" value={reason} onChange={(e) => setReason(e.target.value)} error={errors.reason} placeholder="Fatigue kritis di sekitar terumbu." />
            <TextAreaField id="z-note" label="Catatan (opsional)" value={note} onChange={(e) => setNote(e.target.value)} error={errors.note} placeholder="Ringkasan rapat, pihak yang hadir…" />
            {errors.grid_ids && <p className="t-caption text-error">{errors.grid_ids}</p>}
            {banner && (
              <Notice tone="error" role="alert">
                {banner}
              </Notice>
            )}
            <div className="flex gap-3 pt-1">
              <ButtonLink href="/dashboard" variant="secondary" className="w-[120px]">
                Batal
              </ButtonLink>
              <Button type="submit" className="flex-1" disabled={busy || !p || usable.length === 0}>
                {busy ? "Menyimpan…" : "Simpan keputusan"}
              </Button>
            </div>
          </form>
        </Card>
      </div>
    </>
  );
}
