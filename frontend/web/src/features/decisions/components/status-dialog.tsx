"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/card";
import { Dialog } from "@/components/ui/dialog";
import { SelectField, TextAreaField } from "@/components/ui/field";
import { STATUS_HINT, STATUS_LABEL } from "../format";
import { validateReason, validateRules, type FieldErrors } from "../schemas";
import { editZoneStatus } from "../services/zones";
import { ApiError, type GridStatus, type ZoneDetail } from "../types";
import { draftFromRules, RulesFields, rulesFromDraft } from "./zone-parts";

type Target = Pick<ZoneDetail, "id" | "name" | "status" | "version" | "rules">;

/** api_admin_edit_zone_status. `normal` returns the grids to normal (zone archived). */
export function StatusDialog({
  zone,
  initial,
  open,
  onClose,
  onDone,
}: {
  zone: Target;
  initial?: GridStatus;
  open: boolean;
  onClose: () => void;
  onDone: (status: GridStatus) => void;
}) {
  const options = (["normal", "restricted", "rehab"] as const).filter((s) => s !== zone.status);
  const [status, setStatus] = useState<GridStatus>(initial ?? options[0]);
  const [reason, setReason] = useState("");
  const [rules, setRules] = useState(() => draftFromRules(zone.rules));
  const [errors, setErrors] = useState<FieldErrors>({});
  const [banner, setBanner] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit() {
    const r = status === "restricted" ? rulesFromDraft(rules) : null;
    const errs = { ...validateReason(reason), ...(status === "restricted" ? validateRules("restricted", r) : {}) };
    setErrors(errs);
    if (Object.keys(errs).length) return;
    setBusy(true);
    setBanner("");
    try {
      await editZoneStatus(zone.id, { status, reason, rules: r, version: zone.version });
      onDone(status);
    } catch (e) {
      setBanner(e instanceof ApiError ? e.message : "Gagal mengubah status.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={open} onClose={onClose} title={`Ubah status "${zone.name}"`}>
      <SelectField id="st-status" label="Status baru" value={status} onChange={(e) => setStatus(e.target.value as GridStatus)}>
        {options.map((s) => (
          <option key={s} value={s}>
            {STATUS_LABEL[s]}
          </option>
        ))}
      </SelectField>
      <p className="t-body text-ink-2">{STATUS_HINT[status]}</p>
      {status === "normal" && (
        <Notice tone="info">Zona diarsipkan, semua gridnya kembali normal dan bisa dipilih lagi untuk keputusan baru.</Notice>
      )}
      {status === "restricted" && <RulesFields value={rules} onChange={setRules} errors={errors} idPrefix="st" />}
      <TextAreaField id="st-reason" label="Alasan perubahan" value={reason} onChange={(e) => setReason(e.target.value)} error={errors.reason} />
      {banner && (
        <Notice tone="error" role="alert">
          {banner}
        </Notice>
      )}
      <div className="grid grid-cols-2 gap-4 pt-1">
        <Button variant="secondary" onClick={onClose} autoFocus>
          Batal
        </Button>
        <Button onClick={submit} disabled={busy}>
          {busy ? "Menyimpan…" : status === "normal" ? "Kembalikan ke normal" : "Simpan status"}
        </Button>
      </div>
    </Dialog>
  );
}
