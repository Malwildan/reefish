"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/card";
import { Dialog } from "@/components/ui/dialog";
import { Field, TextAreaField } from "@/components/ui/field";
import { fmtDate, fromDateInput, toDateInput } from "@/features/decisions/format";
import { validateReason } from "@/features/decisions/schemas";
import { dismissFlags } from "@/features/decisions/services/zones";
import { ApiError } from "@/lib/api/error";

const DAY = 86_400_000;

/** api_admin_dismiss_flags: hide system flags until a date (default +30 days, at most +180). */
export function DismissDialog({ gridIds, onClose }: { gridIds: string[]; onClose: (changed: boolean) => void }) {
  const [today] = useState(() => Date.now());
  const [until, setUntil] = useState(() => toDateInput(new Date(today + 30 * DAY).toISOString()));
  const [reason, setReason] = useState("");
  const [errors, setErrors] = useState<{ reason?: string; until?: string }>({});
  const [banner, setBanner] = useState("");
  const [result, setResult] = useState<string>("");
  const [busy, setBusy] = useState(false);
  const max = toDateInput(new Date(today + 180 * DAY).toISOString());
  const min = toDateInput(new Date(today + DAY).toISOString());

  async function submit() {
    const e: typeof errors = { ...validateReason(reason) };
    if (!until || until < min || until > max) e.until = "Pilih tanggal 1–180 hari dari sekarang.";
    setErrors(e);
    if (Object.keys(e).length) return;
    setBusy(true);
    setBanner("");
    try {
      const r = await dismissFlags({ grid_ids: gridIds, reason, until: fromDateInput(until) });
      setResult(
        `${r.dismissed_grid_ids.length} grid di-dismiss sampai ${fmtDate(r.until)}` +
          (r.skipped_grid_ids.length ? ` · ${r.skipped_grid_ids.length} dilewati (bukan flag aktif)` : ""),
      );
    } catch (err) {
      setBanner(err instanceof ApiError ? err.message : "Gagal men-dismiss flag.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onClose={() => onClose(!!result)} title={`Dismiss ${gridIds.length} flag sistem`}>
      <p className="t-body text-ink-2">
        Grid tetap normal dan tidak ditandai ulang oleh sistem sampai tanggal yang dipilih: {gridIds.slice(0, 6).join(", ")}
        {gridIds.length > 6 ? ` +${gridIds.length - 6}` : ""}.
      </p>
      {result ? (
        <Notice tone="success" role="status">
          {result}
        </Notice>
      ) : (
        <>
          <Field id="ds-until" label="Dismiss sampai" type="date" min={min} max={max} value={until} onChange={(e) => setUntil(e.target.value)} error={errors.until} />
          <TextAreaField id="ds-reason" label="Alasan" value={reason} onChange={(e) => setReason(e.target.value)} error={errors.reason} placeholder="Musim pemijahan; dipantau ulang bulan depan" />
        </>
      )}
      {banner && (
        <Notice tone="error" role="alert">
          {banner}
        </Notice>
      )}
      <div className="grid grid-cols-2 gap-4 pt-1">
        <Button variant="secondary" onClick={() => onClose(!!result)} autoFocus>
          {result ? "Tutup" : "Batal"}
        </Button>
        {!result && (
          <Button onClick={submit} disabled={busy}>
            {busy ? "Menyimpan…" : "Dismiss"}
          </Button>
        )}
      </div>
    </Dialog>
  );
}
