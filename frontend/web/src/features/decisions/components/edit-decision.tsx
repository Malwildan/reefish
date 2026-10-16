"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card, Notice } from "@/components/ui/card";
import { Field, InfoBox, TextAreaField } from "@/components/ui/field";
import { fromDateInput, STATUS_LABEL, toDateInput } from "../format";
import { useZoneQuery } from "../hooks/use-zones";
import { validateEdit, type FieldErrors } from "../schemas";
import { editZone, zoneDetail } from "../services/zones";
import { ApiError, type EditZoneInput, type ZoneDetailWithAggregate } from "../types";
import { QueryError, Skeleton } from "./query-state";
import { draftFromRules, RulesFields, rulesFromDraft } from "./zone-parts";

export function EditDecision({ id }: { id: string }) {
  const zone = useZoneQuery(`zone:${id}`, () => zoneDetail(id));
  if (zone.error) return <QueryError error={zone.error} retry={zone.retry} />;
  if (!zone.data) return <Skeleton h={480} />;
  if (!zone.data.is_active) {
    return (
      <Card className="flex max-w-[560px] flex-col gap-4">
        <h1 className="t-title-m">Zona sudah kembali normal</h1>
        <p className="t-body text-ink-2">Zona yang sudah dikembalikan ke normal hanya bisa dilihat di riwayat.</p>
        <ButtonLink href={`/area/${id}`} variant="secondary">
          Lihat keputusan
        </ButtonLink>
      </Card>
    );
  }
  // key: start from the loaded version; a newer version remounts the form
  return <EditForm key={zone.data.version} z={zone.data} />;
}

/** api_admin_edit_zone: name, rules, validity and note. Status and grids change elsewhere. */
function EditForm({ z }: { z: ZoneDetailWithAggregate }) {
  const router = useRouter();
  const [name, setName] = useState(z.name);
  const [rules, setRules] = useState(() => draftFromRules(z.rules));
  const [from, setFrom] = useState(toDateInput(z.effective_from));
  const [until, setUntil] = useState(toDateInput(z.effective_until));
  const [note, setNote] = useState(z.note ?? "");
  const [reason, setReason] = useState("");
  const [errors, setErrors] = useState<FieldErrors>({});
  const [banner, setBanner] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const p: EditZoneInput = {
      name,
      rules: z.status === "restricted" ? rulesFromDraft(rules) : undefined,
      effective_from: fromDateInput(from) ?? z.effective_from,
      effective_until: fromDateInput(until),
      note: note || null,
      reason,
      version: z.version,
    };
    const errs = validateEdit(p, z.status);
    setErrors(errs);
    if (Object.keys(errs).length) return setBanner("Periksa kembali isian yang ditandai.");
    setBusy(true);
    setBanner("");
    try {
      await editZone(z.id, p);
      router.push(`/area/${z.id}?notice=disimpan`);
    } catch (err) {
      setBusy(false);
      if (!(err instanceof ApiError)) return setBanner("Gagal menyimpan.");
      if (err.code === "VALIDATION_ERROR") setErrors((err.details?.fields as FieldErrors) ?? {});
      if (err.code === "ZONE_NAME_TAKEN") setErrors({ name: err.message });
      setBanner(err.message);
    }
  }

  return (
    <>
      <PageHeader title={`Edit ${z.name}`} subtitle="Status dan grid diubah dari detail keputusan; perubahan tercatat di riwayat." />
      <Card className="flex max-w-[720px] flex-col gap-4">
        <form noValidate onSubmit={submit} className="flex flex-col gap-4">
          <Field id="e-name" label="Nama zona" value={name} onChange={(e) => setName(e.target.value)} error={errors.name} />
          <InfoBox label="Status">{STATUS_LABEL[z.status]}</InfoBox>
          {z.status === "restricted" && <RulesFields value={rules} onChange={setRules} errors={errors} capacity={z.aggregate} idPrefix="e" />}
          <div className="grid grid-cols-2 gap-3">
            <Field id="e-from" label="Berlaku mulai" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
            <Field id="e-until" label="Berakhir (opsional)" type="date" value={until} onChange={(e) => setUntil(e.target.value)} error={errors.effective_until} />
          </div>
          <TextAreaField id="e-note" label="Catatan" value={note} onChange={(e) => setNote(e.target.value)} error={errors.note} />
          <TextAreaField id="e-reason" label="Alasan perubahan" value={reason} onChange={(e) => setReason(e.target.value)} error={errors.reason} />
          {banner && (
            <Notice tone="error" role="alert">
              {banner}
            </Notice>
          )}
          <div className="flex gap-3">
            <ButtonLink href={`/area/${z.id}`} variant="secondary" className="w-[120px]">
              Batal
            </ButtonLink>
            <Button type="submit" className="flex-1" disabled={busy}>
              {busy ? "Menyimpan…" : "Simpan perubahan"}
            </Button>
          </div>
        </form>
      </Card>
    </>
  );
}
