"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Badge, Card, Divider, Notice } from "@/components/ui/card";
import { STATUS_LABEL, STATUS_TONE, fmtValidity, num } from "@/features/decisions/format";
import { useZoneQuery } from "@/features/decisions/hooks/use-zones";
import { autoFlaggedGrids, listZones, zoneGridIndex } from "@/features/decisions/services/zones";
import { MapFilters } from "@/features/geo/components/filters";
import { HeatmapMap, LEGEND } from "@/features/geo/components/heatmap-map";
import { useHeatmap } from "@/features/geo/hooks/use-heatmap";
import type { HeatCell } from "@/features/geo/services/heatmap";

const NO_CELLS: HeatCell[] = [];
const NOTICES: Record<string, string> = { normal: "Zona dikembalikan ke normal" };

export function DashboardView({ notice, empty }: { notice?: string; empty?: boolean }) {
  const router = useRouter();
  const [selected, setSelected] = useState<string[]>([]);
  const [hint, setHint] = useState("");
  const [period, setPeriod] = useState<"7d" | "30d">("30d");
  const heatmap = useHeatmap(period);
  const index = useZoneQuery("grid-index", zoneGridIndex);
  const zones = useZoneQuery("zones-active", () => listZones());
  const flags = useZoneQuery("auto-flags", autoFlaggedGrids);
  const autoFlag = useMemo(() => (empty ? [] : (flags.data ?? [])), [flags.data, empty]);

  const cells = empty ? NO_CELLS : (heatmap.data?.cells ?? NO_CELLS);
  const { rehab, restricted } = useMemo(() => {
    const r = { rehab: [] as string[], restricted: [] as string[] };
    if (!empty) for (const [g, z] of Object.entries(index.data ?? {})) r[z.status].push(g);
    return r;
  }, [index.data, empty]);
  // rehab is zero tolerance and decided in its zone; restricted (admin zone or system flag)
  // still needs an admin decision, so it stays selectable
  function toggle(id: string) {
    const z = index.data?.[id];
    if (z?.status === "rehab") {
      setHint(`${id} ada di zona rehab "${z.name}" (grid dinonaktifkan). Ubah lewat detail keputusan zona tersebut.`);
      return;
    }
    setHint(
      z && !selected.includes(id)
        ? `${id} ada di zona restricted "${z.name}". Keputusan baru akan memindahkannya dari zona tersebut.`
        : "",
    );
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));
  }

  const pick = useMemo(() => {
    const selectedIds = new Set(selected);
    const cs = cells.filter((c) => selectedIds.has(c.id));
    return {
      trips: cs.length === selected.length && cs.every((c) => c.trips !== null) ? cs.reduce((t, c) => t + (c.trips ?? 0), 0) : null,
      coral: cs.length === selected.length ? cs.filter((c) => c.hasCoral).length : null,
      auto: selected.filter((g) => autoFlag.includes(g)).length,
      zoned: selected.filter((g) => index.data?.[g]?.status === "restricted").length,
    };
  }, [cells, selected, autoFlag, index.data]);

  const demo = heatmap.data?.source === "demo";
  const liveLegend = demo
    ? [LEGEND.low, LEGEND.high, LEGEND.none, LEGEND.auto, LEGEND.restricted, LEGEND.rehab]
    : [LEGEND.healthy, LEGEND.tired, LEGEND.critical, LEGEND.auto, LEGEND.restricted, LEGEND.rehab];
  const subtitle = heatmap.data
    ? `Heatmap v${heatmap.data.heatmap_version} · ${heatmap.data.window}`
    : "Data heatmap kawasan";

  const policyError = index.error ?? zones.error ?? flags.error;
  const canDecide = selected.length > 0 && !index.loading && !policyError && !heatmap.error;

  return (
    <>
      <PageHeader
        title="Dashboard"
        subtitle={
          empty
            ? "Ringkasan aktivitas kawasan dan keputusan · belum ada data"
            : "Pilih grid di peta untuk membuat keputusan zona"
        }
        badge={notice && NOTICES[notice] ? NOTICES[notice] : empty ? "BELUM ADA DATA" : heatmap.error ? "DATA TIDAK TERSEDIA" : heatmap.loading ? "MEMUAT DATA" : demo ? "DATA DEMO" : "DATA KAWASAN"}
        badgeTone={notice && NOTICES[notice] ? "success" : heatmap.error ? "error" : "info"}
      />

      <div className="flex items-start justify-between gap-4">
        <MapFilters value={period} onChange={setPeriod} />
        {empty && (
          <ButtonLink href="/dashboard" variant="secondary" className="w-[226px]">
            Tampilkan data kawasan
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
                : "Klik sel di peta untuk memilih. Grid normal dan restricted bisa dipilih; grid rehab terkunci."}
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
      {!empty && policyError && (
        <Notice tone="error" role="alert" className="flex items-center justify-between gap-4">
          <span>Status kawasan gagal dimuat: {policyError.message}</span>
          <Button variant="secondary" onClick={() => { index.retry(); zones.retry(); flags.retry(); }}>Coba lagi</Button>
        </Notice>
      )}
      {!empty && heatmap.error && (
        <Notice tone="error" role="alert" className="flex items-center justify-between gap-4">
          <span>Heatmap gagal dimuat: {heatmap.error.message}</span>
          <Button variant="secondary" className="w-[130px]" onClick={heatmap.retry}>Coba lagi</Button>
        </Notice>
      )}

      <div className="grid grid-cols-[minmax(0,1fr)_372px] items-start gap-5">
        <HeatmapMap
          cells={cells}
          rehab={rehab}
          restricted={restricted}
          autoFlag={autoFlag}
          selected={selected}
          onCellClick={empty ? undefined : toggle}
          title={demo ? "Nelayan unik per grid · demo" : "Fatigue per grid · heatmap Supabase"}
          subtitle={subtitle}
          legend={empty ? undefined : liveLegend}
          height={520}
          overlay={
            empty ? (
              <p className="absolute top-1/2 left-1/2 z-10 w-[244px] -translate-x-1/2 -translate-y-1/2 rounded-2xl bg-info-bg px-4 py-3 t-body text-info">
                Belum ada data pada tampilan ini. Muat data kawasan untuk melanjutkan.
              </p>
            ) : heatmap.error ? (
              <p className="absolute top-1/2 left-1/2 z-10 w-[280px] -translate-x-1/2 -translate-y-1/2 rounded-2xl bg-surface px-4 py-3 t-body text-error">
                Heatmap tidak tersedia. Periksa koneksi, lalu coba lagi.
              </p>
            ) : heatmap.loading ? (
              <p className="absolute top-1/2 left-1/2 z-10 -translate-x-1/2 -translate-y-1/2 rounded-2xl bg-surface px-4 py-3 t-body text-ink-2">
                Memuat data heatmap…
              </p>
            ) : cells.length === 0 ? (
              <p className="absolute top-1/2 left-1/2 z-10 w-[280px] -translate-x-1/2 -translate-y-1/2 rounded-2xl bg-surface px-4 py-3 t-body text-ink-2">
                Belum ada sel heatmap relevan pada periode ini.
              </p>
            ) : null
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
                <Metric value={pick.trips == null ? "—" : pick.trips} label={pick.trips == null ? "trip · belum tersedia di api_heatmap" : `trip tercatat (${heatmap.data?.window ?? period})`} />
                <Metric value={pick.coral == null ? "—" : `${pick.coral} grid`} label={pick.coral == null ? "terumbu · tidak tersedia untuk semua grid terpilih" : "berisi terumbu karang"} />
                <Metric value={`${pick.auto} grid`} label="restricted flag sistem" />
                <Metric value={`${pick.zoned} grid`} label="dari zona restricted (akan dipindah)" />
              </div>
            </>
          ) : (
            <>
              <div className="flex flex-col gap-1">
                <h2 className="t-title-m">Ringkasan kawasan</h2>
                <p className="t-body text-ink-2">
                  {empty ? "Belum ada input untuk periode terpilih" : "Data pada periode dan filter terpilih"}
                </p>
              </div>
              <div className="flex flex-col gap-4">
                <Metric big value="—" label="nelayan unik · tidak tersedia di api_heatmap" />
                <Divider />
                <Metric value="—" label="trip tercatat · tidak tersedia di api_heatmap" />
                <Metric value="—" label="jam menangkap · tidak tersedia di api_heatmap" />
                {!empty && (
                  <Metric value={`${autoFlag.length} grid`} label="restricted flag sistem, menunggu keputusan admin" />
                )}
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
          {zones.loading && !zones.data && <p className="t-body text-ink-2">Memuat zona…</p>}
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
