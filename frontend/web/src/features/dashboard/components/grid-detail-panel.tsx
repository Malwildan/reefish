"use client";

import Link from "next/link";
import { Badge, Card } from "@/components/ui/card";
import { QueryError, Skeleton } from "@/features/decisions/components/query-state";
import { fmtDateTime, num, STATUS_LABEL, STATUS_TONE } from "@/features/decisions/format";
import { useZoneQuery } from "@/features/decisions/hooks/use-zones";
import { gridDetail } from "@/features/decisions/services/zones";

const LEVEL = { healthy: "Sehat", tired: "Lelah", critical: "Kritis" } as const;

/** api_admin_grid_detail for the last clicked cell. */
export function GridDetailPanel({ gridId, onClose }: { gridId: string; onClose: () => void }) {
  const q = useZoneQuery(`grid:${gridId}`, () => gridDetail(gridId));
  if (q.error) return <QueryError error={q.error} retry={q.retry} />;
  const d = q.data?.grid_id === gridId ? q.data : undefined;
  if (!d) return <Skeleton h={260} />;
  const s = d.stats;
  const trend = d.fatigue_trend_30d;
  return (
    <Card className="flex flex-col gap-3">
      <div className="flex items-center gap-2">
        <h2 className="flex-1 t-title-m">Grid {d.grid_id}</h2>
        <button type="button" onClick={onClose} className="t-caption text-ink-2 underline" aria-label="Tutup detail grid">
          Tutup
        </button>
      </div>
      <div className="flex flex-wrap gap-2">
        {d.zone ? (
          <Link href={`/area/${d.zone.id}`}>
            <Badge tone={STATUS_TONE[d.zone.status]}>
              {STATUS_LABEL[d.zone.status]} · {d.zone.name}
            </Badge>
          </Link>
        ) : d.auto_flag ? (
          <Badge tone="warning">Restricted · flag sistem</Badge>
        ) : (
          <Badge tone="info">Normal</Badge>
        )}
        {d.has_coral && <Badge tone="success">Terumbu karang</Badge>}
        {d.suggestion === "reopen" && <Badge tone="success">Saran buka kembali</Badge>}
      </div>
      {s ? (
        <dl className="grid grid-cols-2 gap-2 t-body">
          <Item label="Fatigue" value={`${num(s.fatigue_index, 2)}${s.fatigue_level ? ` · ${LEVEL[s.fatigue_level]}` : ""}`} />
          <Item label="Tekanan" value={num(s.pressure_index, 2)} />
          <Item label="Trip 7 / 30 hari" value={`${s.trip_count_7d} / ${s.trip_count_30d}`} />
          <Item label="Tangkapan 30 hari" value={`${num(s.catch_kg_30d)} kg`} />
          <Item label="Jam menangkap" value={`${num(s.fishing_hours_30d, 1)} jam`} />
          <Item label="CPUE" value={s.cpue_30d == null ? "—" : `${num(s.cpue_30d, 1)} kg/jam`} />
        </dl>
      ) : (
        <p className="t-body text-ink-2">Belum ada aktivitas tercatat di grid ini.</p>
      )}
      {s?.last_visited_at && <p className="t-caption text-ink-2">Terakhir dikunjungi {fmtDateTime(s.last_visited_at)}</p>}
      {d.auto_flagged_at && <p className="t-caption text-ink-2">Ditandai sistem {fmtDateTime(d.auto_flagged_at)}</p>}
      {trend.length > 1 && (
        <div className="flex flex-col gap-1">
          <p className="t-caption text-ink-2">Tren fatigue 30 hari</p>
          <div className="flex h-12 items-end gap-[2px]" role="img" aria-label={`Fatigue ${trend.map((t) => t[1]).join(", ")}`}>
            {trend.map(([day, v]) => (
              <span
                key={day}
                className={`flex-1 rounded-sm ${v >= 0.7 ? "bg-error" : v >= 0.4 ? "bg-warm" : "bg-blue-600"}`}
                style={{ height: `${Math.max(4, v * 100)}%` }}
                title={`${day}: ${v}`}
              />
            ))}
          </div>
        </div>
      )}
    </Card>
  );
}

function Item({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col rounded-xl bg-subtle px-3 py-2">
      <dt className="t-caption text-ink-2">{label}</dt>
      <dd className="t-label">{value}</dd>
    </div>
  );
}
