"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Badge, Card, Divider, Notice } from "@/components/ui/card";
import { STATUS_LABEL, STATUS_TONE, fmtValidity, num } from "@/features/decisions/format";
import { useZoneQuery } from "@/features/decisions/hooks/use-zones";
import { listZones, zoneGridIndex } from "@/features/decisions/services/zones";
import { MapFilters } from "@/features/geo/components/filters";
import { HeatmapMap, LEGEND } from "@/features/geo/components/heatmap-map";
import { HEATMAP, heatCell, PRIVACY_MIN, REGION_UNIQUE_FISHERS, type HeatCell } from "@/features/geo/mock-heatmap";
import { center, pillLabel, trail, VIOLATIONS } from "@/features/violations/mock";

const REGION = "Sendang Biru–CMC";
const NO_CELLS: HeatCell[] = [];
const NOTICES: Record<string, string> = { normal: "Zona dikembalikan ke normal" };

export function DashboardView({ notice, empty }: { notice?: string; empty?: boolean }) {
  const router = useRouter();
  const [selected, setSelected] = useState<string[]>([]);
  const [hint, setHint] = useState("");
  const index = useZoneQuery("grid-index", zoneGridIndex);
  const zones = useZoneQuery("zones-active", () => listZones());

  const cells = empty ? NO_CELLS : HEATMAP;
  const { rehab, restricted } = useMemo(() => {
    const r = { rehab: [] as string[], restricted: [] as string[] };
    if (!empty) for (const [g, z] of Object.entries(index.data ?? {})) r[z.status].push(g);
    return r;
  }, [index.data, empty]);
  const markers = useMemo(
    () =>
      empty
        ? []
        : VIOLATIONS.map((v) => ({
            id: v.id,
            label: pillLabel(v),
            lngLat: center(v),
            anchor: v.pattern === "linger" ? ("bottom" as const) : ("top" as const),
            onClick: () => router.push(`/pantau-pelanggaran?id=${v.id}`),
          })),
    [empty, router],
  );
  const trails = useMemo(() => (empty ? [] : VIOLATIONS.map(trail)), [empty]);

  function toggle(id: string) {
    const z = index.data?.[id];
    if (z) {
      setHint(`${id} sudah masuk zona ${STATUS_LABEL[z.status].toLowerCase()} "${z.name}". Ubah lewat detail keputusan.`);
      return;
    }
    setHint("");
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));
  }

  const pick = useMemo(() => {
    const cs = selected.map(heatCell).filter((c) => !!c);
    return {
      trips: cs.reduce((t, c) => t + c.trips, 0),
      coral: cs.filter((c) => c.hasCoral).length,
      critical: cs.filter((c) => c.fatigueLevel === "critical").length,
    };
  }, [selected]);

  const totals = useMemo(() => {
    const shown = cells.filter((c) => c.fishers >= PRIVACY_MIN);
    return { trips: shown.reduce((s, c) => s + c.trips, 0), hours: shown.reduce((s, c) => s + c.hours, 0) };
  }, [cells]);

  const canDecide = selected.length > 0;

  return (
    <>
      <PageHeader
        title="Dashboard"
        subtitle={
          empty
            ? "Ringkasan aktivitas kawasan dan keputusan · belum ada data"
            : `Pilih grid di peta untuk membuat keputusan zona · ${REGION}`
        }
        badge={notice && NOTICES[notice] ? NOTICES[notice] : empty ? "BELUM ADA DATA" : "DATA SIMULASI"}
        badgeTone={notice && NOTICES[notice] ? "success" : "info"}
      />

      <div className="flex items-start justify-between gap-4">
        <MapFilters />
        {empty && (
          <ButtonLink href="/dashboard" variant="secondary" className="w-[226px]">
            Isi data demo
          </ButtonLink>
        )}
      </div>

      {!empty && (
        <Card className="flex items-center gap-4 py-3" aria-live="polite">
          <div className="flex min-w-0 flex-1 flex-col">
            <p className="t-label">{canDecide ? `${selected.length} grid dipilih` : "Belum ada grid dipilih"}</p>
            <p className="truncate t-caption text-ink-2">
              {canDecide
                ? selected.slice(0, 8).join(", ") + (selected.length > 8 ? ` +${selected.length - 8} lagi` : "")
                : "Klik sel di peta untuk memilih. Grid yang sudah masuk zona tidak bisa dipilih."}
            </p>
          </div>
          {canDecide && (
            <Button variant="secondary" className="w-[150px]" onClick={() => setSelected([])}>
              Hapus pilihan
            </Button>
          )}
          <Button
            className="w-[194px]"
            disabled={!canDecide}
            aria-describedby="decide-help"
            onClick={() => router.push(`/area/baru?grids=${selected.join(",")}`)}
          >
            Buat keputusan
          </Button>
          <span id="decide-help" className="sr-only">
            Aktif setelah minimal satu grid dipilih.
          </span>
        </Card>
      )}
      {hint && (
        <Notice tone="warning" role="status">
          {hint}
        </Notice>
      )}

      <div className="grid grid-cols-[minmax(0,1fr)_372px] items-start gap-5">
        <HeatmapMap
          cells={cells}
          rehab={rehab}
          restricted={restricted}
          selected={selected}
          markers={markers}
          trails={trails}
          onCellClick={empty ? undefined : toggle}
          title="Nelayan unik per grid"
          subtitle="4 minggu tertutup · klik untuk memilih"
          legend={empty ? undefined : [LEGEND.low, LEGEND.high, LEGEND.none, LEGEND.restricted, LEGEND.rehab, LEGEND.flag]}
          height={520}
          overlay={
            empty && (
              <p className="absolute top-1/2 left-1/2 z-10 w-[244px] -translate-x-1/2 -translate-y-1/2 rounded-2xl bg-info-bg px-4 py-3 t-body text-info">
                Belum ada data kawasan. Isi data demo untuk melihat contoh.
              </p>
            )
          }
        />

        <Card className="flex flex-col gap-5 py-[22px]">
          {canDecide ? (
            <>
              <div className="flex flex-col gap-1">
                <h2 className="t-title-m">Grid terpilih</h2>
                <p className="t-body text-ink-2">Agregat lengkap dihitung di halaman pendataan zona.</p>
              </div>
              <div className="flex flex-col gap-4">
                <Metric big value={selected.length} label={`grid · ${num(selected.length * 0.25, 2)} km²`} />
                <Divider />
                <Metric value={pick.trips} label="trip tercatat (30 hari)" />
                <Metric value={`${pick.coral} grid`} label="berisi terumbu karang" />
                <Metric value={`${pick.critical} grid`} label="fatigue kritis" />
              </div>
            </>
          ) : (
            <>
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
                <Metric big value={empty ? "—" : REGION_UNIQUE_FISHERS} label="nelayan unik tercatat" />
                <Divider />
                <Metric value={empty ? "—" : num(totals.trips)} label="trip tercatat" />
                <Metric value={empty ? "—" : `${num(totals.hours)} jam`} label="waktu menangkap" />
              </div>
              {empty && (
                <p className="rounded-2xl bg-info-bg p-4 t-body text-info">
                  Data akan muncul per grid setelah batas privasi terpenuhi.
                </p>
              )}
            </>
          )}
        </Card>
      </div>

      {!empty && (
        <Card className="flex flex-col gap-3 px-6">
          <div className="flex min-h-[66px] items-center gap-3">
            <h2 className="flex-1 t-title-m">Zona aktif</h2>
            <ButtonLink href="/area/riwayat" variant="secondary" className="w-[200px]">
              Riwayat keputusan
            </ButtonLink>
            <ButtonLink href="/area" className="w-[176px]">
              Kelola area
            </ButtonLink>
          </div>
          {zones.data?.length === 0 && <p className="t-body text-ink-2">Belum ada zona aktif. Semua grid berstatus normal.</p>}
          {!zones.data && <p className="t-body text-ink-2">Memuat zona…</p>}
          {zones.data?.map((z) => (
            <Link
              key={z.id}
              href={`/area/${z.id}`}
              className="flex min-h-[66px] items-center gap-3 rounded-2xl px-2 hover:bg-subtle"
            >
              <Badge tone={STATUS_TONE[z.status]} className="w-[104px]">
                {STATUS_LABEL[z.status]}
              </Badge>
              <span className="flex min-w-0 flex-1 flex-col gap-1">
                <span className="t-label">{z.name}</span>
                <span className="truncate t-body text-ink-2">
                  {z.grid_count} grid · {num(z.area_km2, 2)} km² · {fmtValidity(z.effective_from, z.effective_until)}
                </span>
              </span>
              {z.status === "restricted" && (
                <span className={`t-caption ${z.quota_exhausted ? "text-error" : "text-ink-2"}`}>
                  {z.quota_exhausted ? "Kuota habis" : `Sisa ${num(z.quota_remaining_kg)} kg`}
                </span>
              )}
            </Link>
          ))}
        </Card>
      )}
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
