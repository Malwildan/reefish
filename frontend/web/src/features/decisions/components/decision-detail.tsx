"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Badge, Card, Divider, Notice } from "@/components/ui/card";
import { InfoBox, TextAreaField } from "@/components/ui/field";
import { HeatmapMap, legendFor } from "@/features/geo/components/heatmap-map";
import { autoFlags, zoneIndex } from "@/features/geo/heatmap-parse";
import { useLiveHeatmap } from "@/features/geo/hooks/use-live-heatmap";
import { getSeaCells, getZoneOutlines } from "@/features/geo/services/heatmap";
import { fmtDateTime, fmtValidity, NOTICE, rulesText, STATUS_HINT, STATUS_LABEL, STATUS_TONE } from "../format";
import { useZoneQuery } from "../hooks/use-zones";
import { validateReason } from "../schemas";
import { editZoneGrids, zoneDetail, zoneHistory } from "../services/zones";
import { ApiError, type ZoneDetailWithAggregate } from "../types";
import { HistoryList } from "./history-list";
import { QueryError, Skeleton } from "./query-state";
import { StatusDialog } from "./status-dialog";
import { AggregatePanel } from "./zone-parts";

export function DecisionDetail({ id, notice }: { id: string; notice?: string }) {
  const router = useRouter();
  const zone = useZoneQuery(`zone:${id}`, () => zoneDetail(id));
  const history = useZoneQuery(`history:${id}`, () => zoneHistory(id));
  const heat = useLiveHeatmap("30d");
  const outlines = useZoneQuery(`outlines:${heat.data?.version ?? 0}`, getZoneOutlines);
  const overlays = useMemo(() => ({ outlines: outlines.data }), [outlines.data]);
  const sea = useZoneQuery("sea", getSeaCells);
  const [dialog, setDialog] = useState(false);
  const [draft, setDraft] = useState<string[] | null>(null); // non-null = editing grids

  const index = useMemo(() => (heat.data ? zoneIndex(heat.data) : {}), [heat.data]);
  const flags = useMemo(() => (heat.data ? autoFlags(heat.data) : []), [heat.data]);

  if (zone.error) return <QueryError error={zone.error} retry={zone.retry} />;
  const z = zone.data?.id === id ? zone.data : undefined;
  if (!z) return <Skeleton h={480} />;
  const archived = !z.is_active;
  const editing = draft !== null;
  const shown = draft ?? z.grid_ids;
  // other zones' cells, coloured by their status; own cells take this zone's colour
  const others = Object.entries(index).filter(([g, o]) => o.id !== z.id && !shown.includes(g));

  function toggle(g: string) {
    if (!draft) return;
    const o = index[g];
    if (o && o.id !== z!.id && o.status === "rehab") return; // rehab of another zone stays locked
    setDraft(draft.includes(g) ? draft.filter((x) => x !== g) : [...draft, g]);
  }

  return (
    <>
      <PageHeader
        title={z.name}
        subtitle={archived ? "Zona sudah kembali normal" : `Keputusan zona · ${STATUS_HINT[z.status]}`}
        badge={notice && NOTICE[notice] ? NOTICE[notice] : `VERSI ${z.version}`}
        badgeTone={notice && NOTICE[notice] ? "success" : "info"}
      />
      <div className="grid grid-cols-[minmax(0,1fr)_420px] items-start gap-5">
        <div className="flex min-w-0 flex-col gap-5">
          <HeatmapMap
            sea={sea.data ?? []}
            cells={heat.data?.cells ?? []}
            scale={heat.data?.scale}
            overlays={overlays}
            rehab={[...others.filter(([, o]) => o.status === "rehab").map(([g]) => g), ...(!archived && z.status === "rehab" ? shown : [])]}
            restricted={[
              ...others.filter(([, o]) => o.status === "restricted").map(([g]) => g),
              ...(!archived && z.status === "restricted" ? shown : []),
            ]}
            autoFlag={flags}
            selected={shown}
            onCellClick={editing ? toggle : undefined}
            fitSelected
            title={editing ? `Edit grid · ${shown.length} dipilih` : `Grid zona · ${z.grid_ids.length}`}
            subtitle={editing ? "Klik grid untuk menambah / mengurangi" : archived ? "Grid sudah kembali normal" : STATUS_LABEL[z.status]}
            legend={legendFor("fatigue", heat.data?.scale)}
            height={420}
          />
          {editing && <EditGrids z={z} draft={draft} onCancel={() => setDraft(null)} onSaved={() => setDraft(null)} />}
          <AggregatePanel a={z.aggregate} title="Agregat zona" />
          <Card className="flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <h2 className="t-title-m">Riwayat keputusan</h2>
              <ButtonLink href="/area/riwayat" variant="secondary" className="w-[180px]">
                Semua riwayat
              </ButtonLink>
            </div>
            {history.error ? (
              <QueryError error={history.error} retry={history.retry} />
            ) : history.data ? (
              <HistoryList items={history.data} />
            ) : (
              <Skeleton h={120} />
            )}
          </Card>
        </div>

        <Card className="flex flex-col gap-4">
          <div className="flex items-center gap-2">
            <Badge tone={archived ? "info" : STATUS_TONE[z.status]}>{archived ? "Normal" : STATUS_LABEL[z.status]}</Badge>
            <span className="t-caption text-ink-2">versi {z.version}</span>
          </div>
          {archived && (
            <Notice tone="info">
              Kembali normal sejak {fmtDateTime(z.archived_at)}. Datanya tetap tersimpan sebagai riwayat.
            </Notice>
          )}
          {!archived && z.status === "rehab" && <Notice tone="error">Zero tolerance: semua grid zona dinonaktifkan untuk penangkapan.</Notice>}
          {archived && <InfoBox label="Status sebelum kembali normal">{STATUS_LABEL[z.status]}</InfoBox>}
          {z.status === "restricted" && <InfoBox label="Kuota agregat">{rulesText(z.rules)}</InfoBox>}
          <InfoBox label="Masa berlaku">{fmtValidity(z.effective_from, z.effective_until)}</InfoBox>
          <InfoBox label="Alasan">{z.reason}</InfoBox>
          <InfoBox label="Catatan">{z.note ?? "—"}</InfoBox>
          <InfoBox label="Grid">{z.grid_ids.join(", ")}</InfoBox>
          <Divider />
          {!archived && !editing && (
            <>
              <ButtonLink href={`/area/${z.id}/edit`} variant="secondary">
                Edit data & kuota
              </ButtonLink>
              <Button variant="secondary" onClick={() => setDraft(z.grid_ids)}>
                Edit grid
              </Button>
              <Button onClick={() => setDialog(true)}>Ubah status</Button>
            </>
          )}
          <ButtonLink href="/dashboard" variant="secondary">
            Kembali ke Dashboard
          </ButtonLink>
        </Card>
      </div>
      {dialog && (
        <StatusDialog
          zone={z}
          open
          onClose={() => setDialog(false)}
          onDone={(s) => {
            setDialog(false);
            router.replace(`/area/${z.id}?notice=${s === "normal" ? "normal" : "status"}`);
          }}
        />
      )}
    </>
  );
}

/** api_admin_edit_zone_grids: add/remove cells, with a reason; restricted cells of other zones move here. */
function EditGrids({
  z,
  draft,
  onCancel,
  onSaved,
}: {
  z: ZoneDetailWithAggregate;
  draft: string[];
  onCancel: () => void;
  onSaved: () => void;
}) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const add = draft.filter((g) => !z.grid_ids.includes(g));
  const remove = z.grid_ids.filter((g) => !draft.includes(g));

  async function save() {
    if (!add.length && !remove.length) return setError("Belum ada grid yang ditambah atau dikurangi.");
    if (!draft.length) return setError("Zona tidak boleh kosong. Untuk melepas semua grid, gunakan Ubah status → Normal.");
    const e = validateReason(reason);
    if (e.reason) return setError(e.reason);
    setBusy(true);
    setError("");
    try {
      await editZoneGrids(z.id, { add, remove, reason, version: z.version });
      onSaved();
    } catch (err) {
      setBusy(false);
      if (!(err instanceof ApiError)) return setError("Gagal menyimpan grid.");
      setError(
        err.code === "ZONE_EMPTY"
          ? "Zona tidak boleh kosong. Untuk melepas semua grid, gunakan Ubah status → Normal."
          : err.code === "VERSION_CONFLICT"
            ? "Zona sudah diubah orang lain. Muat ulang halaman."
            : err.message,
      );
    }
  }

  return (
    <Card className="flex flex-col gap-3">
      <h2 className="t-title-m">Ubah grid zona</h2>
      <p className="t-body text-ink-2">
        Tambah {add.length} grid{add.length ? ` (${add.join(", ")})` : ""} · kurangi {remove.length} grid
        {remove.length ? ` (${remove.join(", ")})` : ""}. Grid restricted dari zona lain akan dipindah ke zona ini; grid rehab zona
        lain terkunci.
      </p>
      <TextAreaField id="eg-reason" label="Alasan perubahan grid" value={reason} onChange={(e) => setReason(e.target.value)} />
      {error && (
        <Notice tone="error" role="alert">
          {error}
        </Notice>
      )}
      <div className="flex gap-3">
        <Button variant="secondary" className="w-[140px]" onClick={onCancel}>
          Batal
        </Button>
        <Button className="flex-1" onClick={save} disabled={busy}>
          {busy ? "Menyimpan…" : "Simpan grid"}
        </Button>
      </div>
    </Card>
  );
}
