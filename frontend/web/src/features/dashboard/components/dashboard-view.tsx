"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Badge, Card, Divider, Notice } from "@/components/ui/card";
import { QueryError } from "@/features/decisions/components/query-state";
import { STATUS_LABEL, STATUS_TONE, fmtUntil, num } from "@/features/decisions/format";
import { useZoneQuery } from "@/features/decisions/hooks/use-zones";
import { listZones, statsSummary } from "@/features/decisions/services/zones";
import { DismissDialog } from "@/features/flags/components/dismiss-dialog";
import { MapFilters, type MapLayer, type MapWindow } from "@/features/geo/components/filters";
import { HeatmapMap, legendFor } from "@/features/geo/components/heatmap-map";
import { autoFlags, zoneIndex, type Layer, type MlColumn } from "@/features/geo/heatmap-parse";
import { useLiveHeatmap } from "@/features/geo/hooks/use-live-heatmap";
import { ML_LAYERS, mlStyle } from "@/features/geo/ml-layers";
import { getHabitat, getLayers, getSeaCells, getZoneOutlines } from "@/features/geo/services/heatmap";
import { GridDetailPanel } from "./grid-detail-panel";
import { RefreshDialog } from "./refresh-dialog";
import { SuggestionsCard } from "./suggestions-card";

const REGION = "Sendang Biru–CMC";
const NOTICES: Record<string, string> = { normal: "Zona dikembalikan ke normal" };

export function DashboardView({ notice, grids = [] }: { notice?: string; grids?: string[] }) {
  const router = useRouter();
  const [window, setWindow] = useState<MapWindow>("30d");
  const [layer, setLayer] = useState<MapLayer>("fatigue");
  const [period, setPeriod] = useState<string | null>(null);
  const [habitat, setHabitat] = useState({ coral: false, mangrove: false });
  const [dismiss, setDismiss] = useState<string[] | null>(null);
  // /dashboard?grids=… (from the Flag sistem page) starts with those cells selected
  const [selected, setSelected] = useState<string[]>(grids);
  const [focus, setFocus] = useState<string | null>(null);
  const [hint, setHint] = useState("");
  const [refresh, setRefresh] = useState(false);

  const sea = useZoneQuery("sea", getSeaCells);
  const heat = useLiveHeatmap(window);
  const mlCol = layer.startsWith("ml:") ? (layer.slice(3) as MlColumn) : null;
  // api_layers only when an ML layer is shown; api_habitat only when a habitat toggle is on
  const ml = useZoneQuery(`layers:${mlCol ? (period ?? "latest") : "off"}`, () => (mlCol ? getLayers(period) : Promise.resolve(null)));
  const hab = useZoneQuery(`habitat:${habitat.coral || habitat.mangrove}`, () =>
    habitat.coral || habitat.mangrove ? getHabitat() : Promise.resolve(null),
  );
  const stats = useZoneQuery(`stats:${window}`, () => statsSummary(window));
  const zones = useZoneQuery("zones-active", () => listZones());

  const h = heat.data;
  const outlines = useZoneQuery(`outlines:${h?.version ?? 0}`, getZoneOutlines);
  const mlData = ml.data ?? null;
  const ms = useMemo(() => (mlCol && mlData ? mlStyle(mlData, mlCol) : null), [mlCol, mlData]);
  const overlays = useMemo(
    () => ({
      outlines: outlines.data,
      coral: habitat.coral ? hab.data?.coral : undefined,
      mangrove: habitat.mangrove ? hab.data?.mangrove : undefined,
    }),
    [outlines.data, hab.data, habitat],
  );
  const index = useMemo(() => (h ? zoneIndex(h) : {}), [h]);
  const flags = useMemo(() => (h ? autoFlags(h) : []), [h]);
  const { rehab, restricted } = useMemo(() => {
    const r = { rehab: [] as string[], restricted: [] as string[] };
    for (const [g, z] of Object.entries(index)) r[z.status].push(g);
    return r;
  }, [index]);
  const seaSet = useMemo(() => new Set(sea.data ?? []), [sea.data]);

  // rehab is zero tolerance and decided in its own zone; normal and restricted (admin zone or
  // system flag) still need an admin decision, so they are selectable
  function toggle(id: string) {
    setFocus(id);
    const z = index[id];
    if (z?.status === "rehab") {
      setHint(`${id} ada di zona rehab "${z.name}" (grid dinonaktifkan). Ubah lewat detail zona tersebut.`);
      return;
    }
    if (!seaSet.has(id)) return;
    setHint(z && !selected.includes(id) ? `${id} ada di zona restricted "${z.name}". Keputusan baru akan memindahkannya.` : "");
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));
  }

  function pick(ids: string[]) {
    setSelected((s) => [...new Set([...s, ...ids.filter((g) => index[g]?.status !== "rehab")])]);
    setFocus(ids[0] ?? null);
  }

  const pickStats = useMemo(() => {
    const byId = new Map((h?.cells ?? []).map((c) => [c.id, c]));
    const cs = selected.map((g) => byId.get(g)).filter((c) => !!c);
    const f = cs.map((c) => c.fatigue).filter((v) => v != null);
    return {
      withData: cs.length,
      fatigueAvg: f.length ? f.reduce((a, b) => a + b, 0) / f.length : null,
      auto: selected.filter((g) => flags.includes(g)).length,
      zoned: selected.filter((g) => index[g]?.status === "restricted").length,
    };
  }, [selected, h, flags, index]);

  const loadError = sea.error ?? heat.error ?? ml.error;
  const canDecide = selected.length > 0;
  const cpueMax = h ? (h.scale.cpue.max ?? Math.max(0, ...h.cells.map((c) => c.cpue ?? 0))) : 0;
  const s = stats.data;

  return (
    <>
      <PageHeader
        title="Dashboard"
        subtitle={`Pilih grid di peta untuk membuat keputusan zona · ${REGION}`}
        badge={
          notice && NOTICES[notice]
            ? NOTICES[notice]
            : heat.liveVersion
              ? `Heatmap diperbarui otomatis · versi ${heat.liveVersion}`
              : h
                ? `HEATMAP VERSI ${h.version}`
                : "MEMUAT"
        }
        badgeTone={(notice && NOTICES[notice]) || heat.liveVersion ? "success" : "info"}
      />

      <div className="flex items-start justify-between gap-4">
        <MapFilters
          window={window}
          layer={layer}
          onWindow={setWindow}
          onLayer={setLayer}
          periods={mlData?.periods}
          period={period ?? mlData?.period}
          onPeriod={setPeriod}
          habitat={habitat}
          onHabitat={setHabitat}
        />
        <Button variant="secondary" className="w-[220px]" onClick={() => setRefresh(true)}>
          Hitung ulang heatmap
        </Button>
      </div>

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
      {hint && (
        <Notice tone="warning" role="status">
          {hint}
        </Notice>
      )}
      {loadError && <QueryError error={loadError} retry={sea.error ? sea.retry : heat.error ? heat.reload : ml.retry} />}
      {habitat.coral && hab.data && !hab.data.coral_codebook_confirmed && (
        <p className="t-caption text-ink-2">Terumbu karang: kode 1 dari data sumber, kamus kelas belum dikonfirmasi (sementara).</p>
      )}

      <div className="grid grid-cols-[minmax(0,1fr)_372px] items-start gap-5">
        <HeatmapMap
          sea={sea.data ?? []}
          cells={h?.cells ?? []}
          layer={mlCol ? "fatigue" : (layer as Layer)}
          paint={ms?.paint}
          overlays={overlays}
          scale={h?.scale}
          rehab={rehab}
          restricted={restricted}
          autoFlag={flags}
          selected={selected}
          onCellClick={toggle}
          title={
            mlCol
              ? `${ML_LAYERS.find((l) => l.key === mlCol)?.label} per grid`
              : layer === "fatigue"
                ? "Fatigue per grid"
                : layer === "pressure"
                  ? "Tekanan penangkapan per grid"
                  : "CPUE per grid"
          }
          subtitle={`${mlCol ? `ML ${mlData?.period ?? "…"}` : `${window === "7d" ? "7" : "30"} hari`} · klik untuk memilih`}
          legend={mlCol ? [...(ms?.legend ?? []), ...legendFor("fatigue").slice(-3)] : legendFor(layer as Layer, h?.scale, cpueMax)}
          height={560}
          overlay={
            h &&
            h.cells.length === 0 && (
              <p className="absolute top-20 left-1/2 z-10 w-[280px] -translate-x-1/2 rounded-2xl bg-info-bg px-4 py-3 t-body text-info">
                Belum ada aktivitas tercatat pada periode ini. Grid tetap bisa dipilih.
              </p>
            )
          }
        />

        <div className="flex flex-col gap-5">
          {canDecide && (
            <Card className="flex flex-col gap-3">
              <h2 className="t-title-m">Grid terpilih</h2>
              <p className="t-body text-ink-2">Agregat lengkap dihitung di halaman pendataan zona.</p>
              <Metric big value={selected.length} label={`grid · ${num(selected.length * 0.25, 2)} km²`} />
              <Divider />
              <Metric value={`${pickStats.withData} grid`} label="punya data aktivitas" />
              <Metric value={num(pickStats.fatigueAvg, 2)} label="fatigue rata-rata" />
              <Metric value={`${pickStats.auto} grid`} label="restricted flag sistem" />
              <Metric value={`${pickStats.zoned} grid`} label="dari zona restricted (akan dipindah)" />
            </Card>
          )}
          {focus && (
            <GridDetailPanel
              gridId={focus}
              ml={mlData ? { period: mlData.period, cell: mlData.cells.get(focus) } : undefined}
              onClose={() => setFocus(null)}
            />
          )}
          {!canDecide && !focus && (
            <Card className="flex flex-col gap-4 py-[22px]">
              <div className="flex flex-col gap-1">
                <h2 className="t-title-m">Ringkasan kawasan</h2>
                <p className="t-body text-ink-2">{window === "7d" ? "7" : "30"} hari terakhir</p>
              </div>
              {stats.error && <QueryError error={stats.error} retry={stats.retry} />}
              <Metric big value={s ? num(s.trips.active_fishers) : "—"} label="nelayan aktif" />
              <Divider />
              <Metric value={s ? num(s.trips.count) : "—"} label="trip tercatat" />
              <Metric value={s ? `${num(s.trips.catch_kg)} kg` : "—"} label="tangkapan tercatat" />
              <Metric value={s ? `${s.flags.active} grid` : "—"} label="restricted flag sistem, menunggu keputusan" />
              <Metric
                value={s ? `${s.zones.restricted} restricted · ${s.zones.rehab} rehab` : "—"}
                label={s ? `zona aktif · ${num(s.zones.protected_area_km2, 2)} km² dilindungi` : "zona aktif"}
              />
              <Metric value={s ? num(s.violations.count) : "—"} label="pelanggaran tercatat" />
            </Card>
          )}
        </div>
      </div>

      <SuggestionsCard onPick={pick} onDismiss={setDismiss} />

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
        {zones.error && <QueryError error={zones.error} retry={zones.retry} />}
        {zones.data?.length === 0 && <p className="t-body text-ink-2">Belum ada zona aktif. Semua grid berstatus normal.</p>}
        {!zones.data && !zones.error && <p className="t-body text-ink-2">Memuat zona…</p>}
        {zones.data?.map((z) => (
          <Link key={z.id} href={`/area/${z.id}`} className="flex min-h-[66px] items-center gap-3 rounded-2xl px-2 hover:bg-subtle">
            <Badge tone={STATUS_TONE[z.status]} className="w-[104px]">
              {STATUS_LABEL[z.status]}
            </Badge>
            <span className="flex min-w-0 flex-1 flex-col gap-1">
              <span className="t-label">{z.name}</span>
              <span className="truncate t-body text-ink-2">
                {z.grid_count} grid · {num(z.area_km2, 2)} km² · {fmtUntil(z.effective_until)}
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

      {refresh && <RefreshDialog onClose={() => setRefresh(false)} />}
      {dismiss && <DismissDialog gridIds={dismiss} onClose={() => setDismiss(null)} />}
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
