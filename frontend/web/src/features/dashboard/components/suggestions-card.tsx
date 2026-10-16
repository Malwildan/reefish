"use client";

import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { QueryError } from "@/features/decisions/components/query-state";
import { num } from "@/features/decisions/format";
import { useZoneQuery } from "@/features/decisions/hooks/use-zones";
import { suggestions } from "@/features/decisions/services/zones";

/**
 * api_admin_suggestions: restrict = active system flags (pick them on the map, then decide);
 * reopen = rehab zones whose cells stayed low-fatigue long enough to consider reopening.
 */
export function SuggestionsCard({ onPick }: { onPick: (gridIds: string[]) => void }) {
  const q = useZoneQuery("suggestions", suggestions);
  if (q.error) return <QueryError error={q.error} retry={q.retry} />;
  const restrict = q.data?.restrict?.data ?? [];
  const reopen = q.data?.reopen?.data ?? [];
  return (
    <Card className="flex flex-col gap-4 px-6">
      <h2 className="t-title-m">Saran sistem</h2>
      {!q.data && <p className="t-body text-ink-2">Memuat saran…</p>}
      <section className="flex flex-col gap-2">
        <div className="flex items-center gap-3">
          <h3 className="flex-1 t-label">Restricted otomatis ({q.data?.restrict?.meta.total ?? 0})</h3>
          {restrict.length > 0 && (
            <Button variant="secondary" className="min-h-10 px-4" onClick={() => onPick(restrict.map((r) => r.grid_id))}>
              Pilih semua di peta
            </Button>
          )}
        </div>
        {q.data && restrict.length === 0 && <p className="t-body text-ink-2">Tidak ada grid yang ditandai sistem.</p>}
        <ul className="flex flex-wrap gap-2">
          {restrict.map((r) => (
            <li key={r.grid_id}>
              <button
                type="button"
                onClick={() => onPick([r.grid_id])}
                className="flex flex-col rounded-xl border border-line bg-warning-bg px-3 py-2 text-left text-warning hover:border-warm"
              >
                <span className="t-label">{r.grid_id}</span>
                <span className="t-caption">
                  fatigue {num(r.fatigue_index, 2)} · {r.days_flagged} hari{r.has_coral ? " · karang" : ""}
                </span>
              </button>
            </li>
          ))}
        </ul>
      </section>
      <section className="flex flex-col gap-2">
        <h3 className="t-label">Saran buka kembali ({q.data?.reopen?.meta.total ?? 0})</h3>
        {q.data && reopen.length === 0 && <p className="t-body text-ink-2">Belum ada zona rehab yang memenuhi syarat dibuka kembali.</p>}
        {reopen.map((z) => (
          <Link
            key={z.zone_id}
            href={`/area/${z.zone_id}`}
            className="flex items-center gap-3 rounded-xl bg-success-bg px-3 py-2 text-success hover:brightness-95"
          >
            <span className="flex-1 t-label">{z.name}</span>
            <span className="t-caption">
              {z.suggested_count}/{z.grid_count} grid pulih ({num(z.suggested_pct, 0)}%) · {z.days_low_min} hari fatigue rendah
            </span>
          </Link>
        ))}
      </section>
    </Card>
  );
}
