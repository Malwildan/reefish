"use client";

import { useRouter } from "next/navigation";
import { useMemo } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { ButtonLink } from "@/components/ui/button";
import { Card, Divider } from "@/components/ui/card";
import { fmtRange, KIND_TITLE, NOTICE, STATUS_LABEL } from "@/features/decisions/format";
import { isExpired, useDecisions, type Decision } from "@/features/decisions/services/store";
import { MapFilters } from "@/features/geo/components/filters";
import { HeatmapMap, LEGEND } from "@/features/geo/components/heatmap-map";
import { HEATMAP, heatCell, PRIVACY_MIN, REGION_UNIQUE_FISHERS } from "@/features/geo/mock-heatmap";
import { center, pillLabel, trail, VIOLATIONS } from "@/features/violations/mock";

export const REGION = "Sendang Biru–CMC";
const NO_CELLS: typeof HEATMAP = [];

export function closedCells(decisions: Decision[]) {
  return decisions.filter((d) => d.status === "terbit" && !isExpired(d)).flatMap((d) => d.cells);
}

export function DashboardView({ grid, notice, empty }: { grid?: string; notice?: string; empty?: boolean }) {
  const router = useRouter();
  const decisions = useDecisions();
  const cells = empty ? NO_CELLS : HEATMAP;
  const closed = useMemo(() => (empty ? [] : closedCells(decisions)), [decisions, empty]);
  const selected = grid && heatCell(grid) ? grid : undefined;
  const markers = useMemo(
    () =>
      empty || selected
        ? []
        : VIOLATIONS.map((v) => ({
            id: v.id,
            label: pillLabel(v),
            lngLat: center(v),
            anchor: v.pattern === "linger" ? ("bottom" as const) : ("top" as const),
            onClick: () => router.push(`/pantau-pelanggaran?id=${v.id}`),
          })),
    [empty, selected, router],
  );
  const trails = useMemo(() => (empty || selected ? [] : VIOLATIONS.map(trail)), [empty, selected]);
  const legend = selected
    ? [LEGEND.low, LEGEND.high, LEGEND.none, LEGEND.closed]
    : [LEGEND.low, LEGEND.high, LEGEND.none, LEGEND.closed, LEGEND.flag];
  const firstClosed = closed[0];

  const totals = useMemo(() => {
    const shown = cells.filter((c) => c.fishers >= PRIVACY_MIN);
    return {
      fishers: REGION_UNIQUE_FISHERS, // unique fishers do not add up across cells
      trips: shown.reduce((s, c) => s + c.trips, 0),
      hours: shown.reduce((s, c) => s + c.hours, 0),
    };
  }, [cells]);

  return (
    <>
      <PageHeader
        title={selected ? `Detail grid ${selected}` : "Dashboard"}
        subtitle={
          selected
            ? "Aktivitas tercatat di sekitar lokasi rehab · data simulasi"
            : empty
              ? "Ringkasan aktivitas kawasan dan keputusan · belum ada data"
              : `Ringkasan aktivitas kawasan dan keputusan terbaru · ${REGION}`
        }
        badge={notice && NOTICE[notice] ? NOTICE[notice] : empty ? "BELUM ADA DATA" : "DATA SIMULASI"}
        badgeTone={notice && NOTICE[notice] ? "success" : "info"}
      />

      <div className="flex items-start justify-between gap-4">
        <MapFilters />
        {empty ? (
          <ButtonLink href="/dashboard" variant="secondary" className="w-[226px]">
            Isi data demo
          </ButtonLink>
        ) : (
          !selected && (
            <ButtonLink href="/area/baru" className="w-[194px]">
              + Buat keputusan
            </ButtonLink>
          )
        )}
      </div>

      <div className="grid grid-cols-[minmax(0,1fr)_372px] items-start gap-5">
        <HeatmapMap
          cells={cells}
          closed={closed}
          selected={selected ? [selected] : []}
          markers={markers}
          trails={trails}
          onCellClick={(id) => router.push(`/dashboard?grid=${id}`)}
          title="Nelayan unik per grid"
          subtitle="Minggu tertutup · tanpa titik GPS"
          legend={empty ? undefined : legend}
          height={selected ? 570 : 430}
          overlay={
            empty && (
              <p className="absolute top-1/2 left-1/2 z-10 w-[244px] -translate-x-1/2 -translate-y-1/2 rounded-2xl bg-info-bg px-4 py-3 t-body text-info">
                Belum ada data kawasan. Isi data demo untuk melihat contoh.
              </p>
            )
          }
        />
        {selected ? (
          <GridDetail id={selected} />
        ) : (
          <Card className="flex flex-col gap-5 py-[22px]">
            {!empty && (
              <ButtonLink href="/pantau-pelanggaran" variant="danger">
                Pantau {VIOLATIONS.length} indikasi aktif
              </ButtonLink>
            )}
            <div className="flex flex-col gap-1">
              <h2 className="t-title-m">Ringkasan kawasan</h2>
              <p className="t-body text-ink-2">
                {empty ? "Belum ada input untuk periode terpilih" : "Data pada periode dan filter terpilih"}
              </p>
            </div>
            <div className="flex flex-col gap-4">
              <Metric big value={empty ? "—" : totals.fishers} label="nelayan unik tercatat" />
              <Divider />
              <Metric value={empty ? "—" : totals.trips} label="trip tercatat" />
              <Metric value={empty ? "—" : `${totals.hours} jam`} label="waktu menangkap" />
            </div>
            {empty ? (
              <p className="rounded-2xl bg-info-bg p-4 t-body text-info">
                Data akan muncul per grid setelah batas privasi terpenuhi.
              </p>
            ) : (
              firstClosed && (
                <ButtonLink href={`/dashboard?grid=${firstClosed}`}>Lihat detail {firstClosed}</ButtonLink>
              )
            )}
          </Card>
        )}
      </div>

      {!empty && !selected && <DecisionsCard decisions={decisions} />}
    </>
  );
}

function Metric({ value, label, big }: { value: string | number; label: string; big?: boolean }) {
  return (
    <div className="flex flex-col gap-1">
      <p className={big ? "t-heading-m" : "t-title-m"}>{value}</p>
      <p className="t-body text-ink-2">{label}</p>
    </div>
  );
}

function GridDetail({ id }: { id: string }) {
  const c = heatCell(id)!;
  const hidden = c.fishers < PRIVACY_MIN;
  const max = Math.max(...c.trend);
  return (
    <Card className="flex flex-col gap-8">
      <div className="flex flex-col gap-6">
        <div className="flex flex-col gap-2">
          <h2 className="t-title-m">{id} · 4 minggu</h2>
          <p className="t-body text-ink-2">
            {hidden ? "Data belum cukup untuk ditampilkan" : `${c.fishers} nelayan unik · ${c.trips} trip · ${c.hours} jam`}
          </p>
        </div>
        {!hidden && (
          <>
            <p className="t-body">
              Pancing ulur {c.gear.pancing} trip · Bubu {c.gear.bubu} trip
            </p>
            <p className="t-label">Tren 8 minggu</p>
            <div>
              <div className="flex h-[77px] items-end gap-4" role="img" aria-label={`Trip per minggu: ${c.trend.join(", ")}`}>
                {c.trend.map((t, i) => (
                  <span key={i} className="w-6 rounded-[5px] bg-blue-600" style={{ height: Math.max(8, (t / max) * 77) }} />
                ))}
              </div>
              <div className="mt-2 flex w-[296px] justify-between t-caption text-ink-2">
                <span>8 minggu lalu</span>
                <span>terbaru</span>
              </div>
            </div>
          </>
        )}
        <Divider />
        <p className="t-body">Dekat lokasi rehab · {c.rehabKm.toLocaleString("id-ID")} km</p>
        <p className="t-body">Stres panas NOAA: {c.heatStress} · snapshot</p>
        <p className="t-caption text-ink-2">Aktivitas tercatat bukan tekanan total.</p>
      </div>
      <div className="flex flex-col gap-3">
        <ButtonLink href={`/area/baru?grid=${id}`}>Buat keputusan</ButtonLink>
        <ButtonLink href="/dashboard" variant="secondary">
          Kembali ke Dashboard
        </ButtonLink>
      </div>
    </Card>
  );
}

function DecisionsCard({ decisions }: { decisions: Decision[] }) {
  return (
    <Card className="flex flex-col gap-3 px-6">
      <div className="flex min-h-[66px] items-center gap-3">
        <h2 className="flex-1 t-title-m">Keputusan kawasan</h2>
        <ButtonLink href="/area" className="w-[176px]">
          Kelola area
        </ButtonLink>
      </div>
      {decisions.length === 0 && <p className="t-body text-ink-2">Belum ada keputusan. Buat dari detail grid atau tombol di atas.</p>}
      {decisions.map((d) => {
        const status = isExpired(d) ? "berakhir" : d.status;
        return (
          <div key={d.id} className="flex min-h-[66px] items-center gap-3">
            <div className="flex min-w-0 flex-1 flex-col gap-1">
              <p className="t-label">
                {d.code} · {KIND_TITLE[d.kind]}
              </p>
              <p className="truncate t-body text-ink-2">
                {STATUS_LABEL[status]} · {fmtRange(d.start, d.end)} · {d.reason || "Alasan belum diisi"}
              </p>
            </div>
            <ButtonLink href={`/area/${d.id}`} variant="secondary" className="w-[200px]">
              Lihat keputusan
            </ButtonLink>
            {(status === "draf" || status === "terbit") && (
              <ButtonLink href={`/area/${d.id}/edit`} variant="secondary" className="w-[90px]">
                Edit
              </ButtonLink>
            )}
          </div>
        );
      })}
    </Card>
  );
}
