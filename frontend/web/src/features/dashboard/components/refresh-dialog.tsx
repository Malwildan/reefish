"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/card";
import { Dialog } from "@/components/ui/dialog";
import { TextAreaField } from "@/components/ui/field";
import { num } from "@/features/decisions/format";
import { validateReason } from "@/features/decisions/schemas";
import { refreshHeatmap, refreshStatus } from "@/features/decisions/services/zones";
import { ApiError } from "@/lib/api/error";

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** api_admin_refresh_heatmap (scope all) queues a job; api_admin_refresh_status is polled until it ends. */
export function RefreshDialog({ onClose }: { onClose: () => void }) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string>("");
  const [stage, setStage] = useState("");

  async function run() {
    const e = validateReason(reason);
    if (e.reason) return setError(e.reason);
    setBusy(true);
    setError("");
    try {
      let job = await refreshHeatmap(reason);
      setStage("Menunggu giliran…");
      // the cron worker picks jobs up every 10 s; give up waiting after ~2 minutes
      for (let i = 0; i < 60 && (job.status === "queued" || job.status === "running"); i++) {
        await wait(2000);
        job = await refreshStatus(job.job_id);
        setStage(job.status === "running" ? "Menghitung…" : "Menunggu giliran…");
      }
      if (job.status === "done") setDone(`Selesai · ${num(job.changed_cells)} grid berubah · versi heatmap ${job.heatmap_version}`);
      else if (job.status === "failed") setError(`Hitung ulang gagal: ${job.error ?? "tanpa keterangan"}`);
      else setError("Masih diproses di server. Tutup dialog ini dan muat ulang halaman beberapa saat lagi.");
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
            {busy ? stage || "Mengirim…" : "Hitung ulang"}
          </Button>
        )}
      </div>
    </Dialog>
  );
}
