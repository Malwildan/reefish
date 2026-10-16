"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Badge, Card } from "@/components/ui/card";
import { QueryError, Skeleton } from "@/features/decisions/components/query-state";
import { fmtDate, fmtDateTime, num } from "@/features/decisions/format";
import { useZoneQuery } from "@/features/decisions/hooks/use-zones";
import { listFlags } from "@/features/decisions/services/zones";
import { DismissDialog } from "./dismiss-dialog";

type State = "active" | "dismissed";
type Sort = "-fatigue" | "-flagged_at" | "flagged_at";

/** api_admin_list_flags: restricted flags the system put on normal cells, plus dismissed ones. */
export function FlagsView() {
  const router = useRouter();
  const [state, setState] = useState<State>("active");
  const [coral, setCoral] = useState(false);
  const [sort, setSort] = useState<Sort>("-fatigue");
  const [page, setPage] = useState(1);
  const [picked, setPicked] = useState<string[]>([]);
  const [dismiss, setDismiss] = useState<string[] | null>(null);
  const q = useZoneQuery(`flags:${state}:${coral}:${sort}:${page}`, () =>
    listFlags({ state, hasCoral: coral || undefined, sort, page }),
  );
  const rows = q.data?.data ?? [];
  const total = q.data?.meta.total ?? 0;
  const pages = Math.max(1, Math.ceil(total / 20));
  const reset = (fn: () => void) => {
    fn();
    setPage(1);
    setPicked([]);
  };

  return (
    <>
      <PageHeader
        title="Flag sistem"
        subtitle="Grid normal yang ditandai restricted otomatis oleh sistem (fatigue kritis). Putuskan jadi zona, atau dismiss sementara."
      />
      <div className="flex flex-wrap items-center gap-3">
        {(["active", "dismissed"] as const).map((s) => (
          <button
            key={s}
            type="button"
            aria-pressed={state === s}
            onClick={() => reset(() => setState(s))}
            className={`min-h-10 rounded-full px-4 py-2 t-label ${state === s ? "bg-primary text-inverse" : "bg-surface text-ink hover:bg-subtle"}`}
          >
            {s === "active" ? "Aktif" : "Di-dismiss"}
          </button>
        ))}
        <label className="ml-2 flex items-center gap-2 t-body">
          <input type="checkbox" checked={coral} onChange={(e) => reset(() => setCoral(e.target.checked))} className="size-4 accent-[var(--reefish-action-primary)]" />
          Hanya grid terumbu karang
        </label>
        <label className="ml-auto flex items-center gap-2 t-body">
          Urutkan
          <select
            value={sort}
            onChange={(e) => reset(() => setSort(e.target.value as Sort))}
            className="min-h-10 rounded-xl border border-line bg-surface px-3 t-label"
          >
            <option value="-fatigue">Fatigue tertinggi</option>
            <option value="-flagged_at">Flag terbaru</option>
            <option value="flagged_at">Flag terlama</option>
          </select>
        </label>
      </div>

      {state === "active" && (
        <Card className="flex items-center gap-3 py-3">
          <p className="flex-1 t-label">{picked.length ? `${picked.length} flag dipilih` : "Centang flag untuk diproses"}</p>
          <Button
            variant="secondary"
            className="w-[200px]"
            disabled={!picked.length}
            onClick={() => setDismiss(picked)}
          >
            Dismiss
          </Button>
          <Button className="w-[220px]" disabled={!picked.length} onClick={() => router.push(`/dashboard?grids=${picked.join(",")}`)}>
            Pilih di peta → keputusan
          </Button>
        </Card>
      )}

      {q.error && <QueryError error={q.error} retry={q.retry} />}
      {!q.data && !q.error && <Skeleton h={240} />}
      {q.data && (
        <Card className="flex flex-col gap-2 p-0">
          <table className="w-full t-body">
            <thead className="t-caption text-ink-2">
              <tr className="border-b border-line">
                {state === "active" && (
                  <th className="w-12 px-4 py-3 text-left">
                    <input
                      type="checkbox"
                      aria-label="Pilih semua di halaman ini"
                      checked={rows.length > 0 && rows.every((r) => picked.includes(r.grid_id))}
                      onChange={(e) =>
                        setPicked(e.target.checked ? [...new Set([...picked, ...rows.map((r) => r.grid_id)])] : picked.filter((g) => !rows.some((r) => r.grid_id === g)))
                      }
                      className="size-4 accent-[var(--reefish-action-primary)]"
                    />
                  </th>
                )}
                <th className="px-4 py-3 text-left">Grid</th>
                <th className="px-4 py-3 text-left">Fatigue</th>
                <th className="px-4 py-3 text-left">Ditandai</th>
                <th className="px-4 py-3 text-left">Tetangga ter-flag</th>
                {state === "dismissed" && <th className="px-4 py-3 text-left">Dismiss</th>}
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-4 py-6 text-ink-2">
                    {state === "active" ? "Tidak ada flag aktif." : "Belum ada flag yang di-dismiss."}
                  </td>
                </tr>
              )}
              {rows.map((r) => (
                <tr key={r.grid_id} className="border-b border-line last:border-0">
                  {state === "active" && (
                    <td className="px-4 py-3">
                      <input
                        type="checkbox"
                        aria-label={`Pilih ${r.grid_id}`}
                        checked={picked.includes(r.grid_id)}
                        onChange={(e) => setPicked(e.target.checked ? [...picked, r.grid_id] : picked.filter((g) => g !== r.grid_id))}
                        className="size-4 accent-[var(--reefish-action-primary)]"
                      />
                    </td>
                  )}
                  <td className="px-4 py-3">
                    <span className="t-label">{r.grid_id}</span>
                    {r.has_coral && (
                      <Badge tone="success" className="ml-2 min-h-6 px-2 py-0">
                        Karang
                      </Badge>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <span className={r.fatigue_level === "critical" ? "text-error" : ""}>{num(r.fatigue_index, 2)}</span>
                  </td>
                  <td className="px-4 py-3">
                    {r.flagged_at ? `${fmtDateTime(r.flagged_at)} · ${r.days_flagged} hari` : "—"}
                  </td>
                  <td className="px-4 py-3 text-ink-2">{r.flagged_neighbor_ids.join(", ") || "—"}</td>
                  {state === "dismissed" && (
                    <td className="px-4 py-3 text-ink-2">
                      s.d. {fmtDate(r.dismissed_until)} · {r.dismiss_reason}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
          <div className="flex items-center justify-between px-4 pb-3 t-caption text-ink-2">
            <span>{total} flag</span>
            <span className="flex items-center gap-2">
              <Button variant="secondary" className="min-h-9 px-3" disabled={page <= 1} onClick={() => setPage(page - 1)}>
                Sebelumnya
              </Button>
              Halaman {page} / {pages}
              <Button variant="secondary" className="min-h-9 px-3" disabled={page >= pages} onClick={() => setPage(page + 1)}>
                Berikutnya
              </Button>
            </span>
          </div>
        </Card>
      )}

      {dismiss && (
        <DismissDialog
          gridIds={dismiss}
          onClose={(done) => {
            setDismiss(null);
            if (done) setPicked([]);
          }}
        />
      )}
    </>
  );
}
