"use client";

import Link from "next/link";
import { useMemo } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { ButtonLink } from "@/components/ui/button";
import { Badge, Card } from "@/components/ui/card";
import { HeatmapMap, legendFor } from "@/features/geo/components/heatmap-map";
import { autoFlags, zoneIndex } from "@/features/geo/heatmap-parse";
import { getHeatmap, getSeaCells } from "@/features/geo/services/heatmap";
import { fmtUntil, num, STATUS_LABEL, STATUS_TONE } from "../format";
import { useZoneQuery } from "../hooks/use-zones";
import { listZones } from "../services/zones";
import type { ZoneStatus } from "../types";
import { QueryError, Skeleton } from "./query-state";

const FILTERS: { key: ZoneStatus | "semua"; label: string }[] = [
  { key: "semua", label: "Semua" },
  { key: "restricted", label: "Restricted" },
  { key: "rehab", label: "Rehab" },
];

export function AreaView({ status }: { status?: ZoneStatus }) {
  const zones = useZoneQuery(`zones:${status ?? "all"}`, () => listZones({ status }));
  const heat = useZoneQuery("heat:30d", () => getHeatmap("30d"));
  const sea = useZoneQuery("sea", getSeaCells);
  const { rehab, restricted, flags } = useMemo(() => {
    const r = { rehab: [] as string[], restricted: [] as string[], flags: heat.data ? autoFlags(heat.data) : [] };
    for (const [g, z] of Object.entries(heat.data ? zoneIndex(heat.data) : {})) r[z.status].push(g);
    return r;
  }, [heat.data]);

  return (
    <>
      <PageHeader title="Area kawasan" subtitle="Zona aktif hasil keputusan. Grid lain berstatus normal." />
      <div className="flex items-center justify-between gap-4">
        <nav className="flex gap-2" aria-label="Filter status">
          {FILTERS.map((f) => {
            const on = (status ?? "semua") === f.key;
            return (
              <Link
                key={f.key}
                href={f.key === "semua" ? "/area" : `/area?status=${f.key}`}
                aria-current={on ? "page" : undefined}
                className={`min-h-10 rounded-full px-4 py-2 t-label ${on ? "bg-primary text-inverse" : "bg-surface text-ink hover:bg-subtle"}`}
              >
                {f.label}
              </Link>
            );
          })}
        </nav>
        <div className="flex gap-3">
          <ButtonLink href="/area/riwayat" variant="secondary" className="w-[200px]">
            Riwayat keputusan
          </ButtonLink>
          <ButtonLink href="/dashboard" className="w-[220px]">
            + Pilih grid di dashboard
          </ButtonLink>
        </div>
      </div>
      <div className="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] items-start gap-5">
        <HeatmapMap
          sea={sea.data ?? []}
          cells={heat.data?.cells ?? []}
          scale={heat.data?.scale}
          rehab={rehab}
          restricted={restricted}
          autoFlag={flags}
          title="Peta zona aktif"
          subtitle={`${rehab.length + restricted.length} grid dibatasi`}
          legend={legendFor("fatigue", heat.data?.scale)}
          height={520}
        />
        <div className="flex flex-col gap-4">
          {zones.error && <QueryError error={zones.error} retry={zones.retry} />}
          {!zones.data && !zones.error && <Skeleton h={240} />}
          {zones.data?.length === 0 && (
            <Card className="t-body text-ink-2">Tidak ada zona aktif untuk filter ini.</Card>
          )}
          {zones.data?.map((z) => (
            <Card key={z.id} className="flex flex-col gap-3 p-6">
              <div className="flex items-center gap-3">
                <Badge tone={STATUS_TONE[z.status]}>{STATUS_LABEL[z.status]}</Badge>
                <h2 className="flex-1 t-title-m">{z.name}</h2>
              </div>
              <p className="t-body text-ink-2">
                {z.grid_count} grid · {num(z.area_km2, 2)} km² · fatigue rata-rata {num(z.fatigue_avg, 2)} · maks {num(z.fatigue_max, 2)}
              </p>
              <p className="t-label">{fmtUntil(z.effective_until)}</p>
              {z.status === "restricted" && (
                <p className={`t-body ${z.quota_exhausted ? "text-error" : "text-warning"}`}>
                  {z.quota_exhausted ? "Kuota periode ini habis" : `Sisa kuota ${num(z.quota_remaining_kg)} kg`}
                </p>
              )}
              <div className="flex gap-3">
                <ButtonLink href={`/area/${z.id}`} variant="secondary" className="w-[160px]">
                  Lihat
                </ButtonLink>
                <ButtonLink href={`/area/${z.id}/edit`} variant="secondary" className="w-[160px]">
                  Edit
                </ButtonLink>
              </div>
            </Card>
          ))}
        </div>
      </div>
    </>
  );
}
