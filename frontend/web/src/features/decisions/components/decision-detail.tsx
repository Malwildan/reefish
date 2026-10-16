"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Badge, Card, Divider, Notice } from "@/components/ui/card";
import { InfoBox } from "@/components/ui/field";
import { HeatmapMap } from "@/features/geo/components/heatmap-map";
import { HEATMAP } from "@/features/geo/mock-heatmap";
import { fmtDateTime, fmtValidity, NOTICE, rulesText, STATUS_HINT, STATUS_LABEL, STATUS_TONE } from "../format";
import { useZoneQuery } from "../hooks/use-zones";
import { zoneDetail, zoneHistory } from "../services/zones";
import { HistoryList } from "./history-list";
import { QueryError, Skeleton } from "./query-state";
import { StatusDialog } from "./status-dialog";
import { AggregatePanel } from "./zone-parts";

export function DecisionDetail({ id, notice }: { id: string; notice?: string }) {
  const router = useRouter();
  const zone = useZoneQuery(`zone:${id}`, () => zoneDetail(id));
  const history = useZoneQuery(`history:${id}`, () => zoneHistory(id));
  const [dialog, setDialog] = useState(false);

  if (zone.error) return <QueryError error={zone.error} retry={zone.retry} />;
  const z = zone.data;
  if (!z) return <Skeleton h={480} />;
  const archived = !z.is_active;

  return (
    <>
      <PageHeader
        title={z.name}
        subtitle={archived ? `Kembali normal sejak ${fmtDateTime(z.archived_at)}` : `Keputusan zona · ${STATUS_HINT[z.status]}`}
        badge={notice && NOTICE[notice] ? NOTICE[notice] : "DATA SIMULASI"}
        badgeTone={notice && NOTICE[notice] ? "success" : "info"}
      />
      <div className="grid grid-cols-[minmax(0,1fr)_420px] items-start gap-5">
        <div className="flex min-w-0 flex-col gap-5">
          <HeatmapMap
            cells={HEATMAP}
            rehab={!archived && z.status === "rehab" ? z.grid_ids : []}
            restricted={!archived && z.status === "restricted" ? z.grid_ids : []}
            selected={z.grid_ids}
            fitSelected
            title={`Grid zona · ${z.grid_ids.length}`}
            subtitle={archived ? "Grid sudah kembali normal" : STATUS_LABEL[z.status]}
            height={360}
          />
          <AggregatePanel a={z.aggregate} title="Agregat zona" />
          <Card className="flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <h2 className="t-title-m">Riwayat keputusan</h2>
              <ButtonLink href="/area/riwayat" variant="secondary" className="w-[180px]">
                Semua riwayat
              </ButtonLink>
            </div>
            {history.data ? <HistoryList items={history.data} /> : <Skeleton h={120} />}
          </Card>
        </div>

        <Card className="flex flex-col gap-4">
          <div className="flex items-center gap-2">
            <Badge tone={archived ? "info" : STATUS_TONE[z.status]}>{archived ? "Normal" : STATUS_LABEL[z.status]}</Badge>
            <span className="t-caption text-ink-2">versi {z.version}</span>
          </div>
          {archived && <Notice tone="info">Zona ini sudah kembali normal. Datanya tetap tersimpan sebagai riwayat.</Notice>}
          {!archived && z.status === "rehab" && (
            <Notice tone="error">Zero tolerance: semua grid zona dinonaktifkan untuk penangkapan.</Notice>
          )}
          {archived && <InfoBox label="Status sebelum kembali normal">{STATUS_LABEL[z.status]}</InfoBox>}
          {z.status === "restricted" && <InfoBox label="Kuota agregat">{rulesText(z.rules)}</InfoBox>}
          <InfoBox label="Masa berlaku">{fmtValidity(z.effective_from, z.effective_until)}</InfoBox>
          <InfoBox label="Alasan">{z.reason}</InfoBox>
          <InfoBox label="Catatan">{z.note ?? "—"}</InfoBox>
          <InfoBox label="Grid">{z.grid_ids.join(", ")}</InfoBox>
          <Divider />
          {!archived && (
            <>
              <ButtonLink href={`/area/${z.id}/edit`} variant="secondary">
                Edit data & kuota
              </ButtonLink>
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
