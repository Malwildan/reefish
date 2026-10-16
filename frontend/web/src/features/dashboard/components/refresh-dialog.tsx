"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/card";
import { Dialog } from "@/components/ui/dialog";
import { TextAreaField } from "@/components/ui/field";
import { num } from "@/features/decisions/format";
import { validateReason } from "@/features/decisions/schemas";
import { refreshHeatmap } from "@/features/decisions/services/zones";
import { ApiError } from "@/lib/api/error";

/** api_admin_refresh_heatmap (scope all): recompute fatigue, flags and the published heatmap now. */
export function RefreshDialog({ onClose }: { onClose: () => void }) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string>("");

  async function run() {
    const e = validateReason(reason);
    if (e.reason) return setError(e.reason);
    setBusy(true);
    setError("");
    try {
      const r = await refreshHeatmap(reason);
      setDone(`Selesai · ${num(r.changed_cells)} grid berubah · versi heatmap ${r.heatmap_version}`);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Gagal menghitung ulang.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onClose={onClose} title="Hitung ulang heatmap">
      <p className="t-body text-ink-2">
        Menghitung ulang fatigue, flag sistem, dan heatmap untuk semua grid sekarang (biasanya otomatis tiap hari 00:10 WIB).
      </p>
      {done ? (
        <Notice tone="success" role="status">
          {done}
        </Notice>
      ) : (
        <TextAreaField id="rf-reason" label="Alasan" value={reason} onChange={(e) => setReason(e.target.value)} error={error} />
      )}
      <div className="grid grid-cols-2 gap-4 pt-1">
        <Button variant="secondary" onClick={onClose} autoFocus>
          {done ? "Tutup" : "Batal"}
        </Button>
        {!done && (
          <Button onClick={run} disabled={busy}>
            {busy ? "Menghitung…" : "Hitung ulang"}
          </Button>
        )}
      </div>
    </Dialog>
  );
}
