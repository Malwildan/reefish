"use client";

import Link from "next/link";
import { useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Badge, Card } from "@/components/ui/card";
import { fmtDateTime, fmtValidity, NOTICE, num, STATUS_LABEL, STATUS_TONE } from "../format";
import { useZoneQuery } from "../hooks/use-zones";
import { listZones, zoneDetail, zoneHistory } from "../services/zones";
import type { ZoneDetail, ZoneSummary } from "../types";
import { HistoryList } from "./history-list";
import { QueryError, Skeleton } from "./query-state";
import { StatusDialog } from "./status-dialog";

type Filter = "semua" | "aktif" | "normal";
const FILTERS: { key: Filter; label: string }[] = [
  { key: "semua", label: "Semua" },
  { key: "aktif", label: "Masih berlaku" },
  { key: "normal", label: "Kembali normal" },
];

/** Every decision (active and archived) with its timeline; active ones can be returned to normal. */
export function HistoryView() {
  const [filter, setFilter] = useState<Filter>("semua");
  const [target, setTarget] = useState<ZoneDetail | null>(null);
  const [done, setDone] = useState("");
  const zones = useZoneQuery("zones-all", () => listZones({ includeArchived: true }));
  const history = useZoneQuery("history-all", () => zoneHistory());

  const shown = (zones.data ?? []).filter((z) => filter === "semua" || (filter === "aktif" ? z.is_active : !z.is_active));

  async function openNormal(z: ZoneSummary) {
    setDone("");
    // the dialog needs the current version and rules (api_admin_zone_detail)
    setTarget(await zoneDetail(z.id));
  }

  return (
    <>
      <PageHeader
        title="Riwayat keputusan"
        subtitle="Semua keputusan zona beserta perubahannya. Zona yang masih berlaku bisa dikembalikan ke normal."
        badge={done || "DATA SIMULASI"}
        badgeTone={done ? "success" : "info"}
      />
      <nav className="flex gap-2" aria-label="Filter riwayat">
        {FILTERS.map((f) => (
          <button
            key={f.key}
            type="button"
            aria-pressed={filter === f.key}
            onClick={() => setFilter(f.key)}
            className={`min-h-10 rounded-full px-4 py-2 t-label ${filter === f.key ? "bg-primary text-inverse" : "bg-surface text-ink hover:bg-subtle"}`}
          >
            {f.label}
          </button>
        ))}
      </nav>

      <div className="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] items-start gap-5">
        <Card className="flex flex-col gap-3 p-6">
          <h2 className="t-title-m">Keputusan ({shown.length})</h2>
          {zones.error && <QueryError error={zones.error} retry={zones.retry} />}
          {!zones.data && !zones.error && <Skeleton h={200} />}
          {zones.data && shown.length === 0 && <p className="t-body text-ink-2">Tidak ada keputusan untuk filter ini.</p>}
          <ul className="flex flex-col gap-3">
            {shown.map((z) => (
              <li key={z.id} className="flex flex-col gap-2 rounded-2xl bg-subtle p-4">
                <div className="flex items-center gap-2">
                  <Badge tone={z.is_active ? STATUS_TONE[z.status] : "info"}>{z.is_active ? STATUS_LABEL[z.status] : "Normal"}</Badge>
                  <Link href={`/area/${z.id}`} className="flex-1 t-label underline decoration-line underline-offset-4 hover:decoration-primary">
                    {z.name}
                  </Link>
                </div>
                <p className="t-body text-ink-2">
                  {z.grid_count} grid · {num(z.area_km2, 2)} km² ·{" "}
                  {z.is_active
                    ? fmtValidity(z.effective_from, z.effective_until)
                    : `${STATUS_LABEL[z.status]} → Normal pada ${fmtDateTime(z.archived_at)}`}
                </p>
                {z.is_active && (
                  <Button variant="secondary" className="w-fit px-5" onClick={() => openNormal(z)}>
                    Kembalikan ke normal
                  </Button>
                )}
              </li>
            ))}
          </ul>
        </Card>

        <Card className="flex flex-col gap-4 p-6">
          <h2 className="t-title-m">Linimasa perubahan</h2>
          {history.data ? (
            <HistoryList
              showZone
              items={history.data.filter((h) => shown.some((z) => z.id === h.zone_id))}
            />
          ) : (
            <Skeleton h={240} />
          )}
        </Card>
      </div>

      {target && (
        <StatusDialog
          zone={target}
          initial="normal"
          open
          onClose={() => setTarget(null)}
          onDone={() => {
            setDone(NOTICE.normal);
            setTarget(null);
          }}
        />
      )}
    </>
  );
}
