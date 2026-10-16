"use client";

import { useRouter } from "next/navigation";
import { useCallback, useMemo, useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { HeatmapMap, LEGEND } from "@/features/geo/components/heatmap-map";
import { HEATMAP } from "@/features/geo/mock-heatmap";
import { center, PATTERN, pillLabel, trail, VIOLATIONS, type Violation } from "../mock";

const REGION = "Sendang Biru–CMC";
const REEF_CELLS = ["X099_Y148", "X100_Y148", "X100_Y147", "X101_Y147", "X101_Y146"];

export function ViolationMonitor({ selectedId }: { selectedId?: string }) {
  const router = useRouter();
  // shortcut: sent state lives in the page only; persist it once a warnings RPC exists
  const [sent, setSent] = useState<Record<string, string>>({});
  const selected = VIOLATIONS.find((v) => v.id === selectedId);
  const select = useCallback(
    (id?: string) => router.replace(id ? `/pantau-pelanggaran?id=${id}` : "/pantau-pelanggaran", { scroll: false }),
    [router],
  );

  const markers = useMemo(
    () =>
      VIOLATIONS.map((v) => ({
        id: v.id,
        label: pillLabel(v),
        lngLat: center(v),
        active: v.id === selectedId,
        anchor: v.pattern === "linger" ? ("bottom" as const) : ("top" as const),
        onClick: () => select(v.id),
      })),
    [selectedId, select],
  );
  const trails = useMemo(() => VIOLATIONS.map(trail), []);
  const cells = useMemo(() => HEATMAP.filter((c) => REEF_CELLS.includes(c.id)), []);
  const flagged = useMemo(() => VIOLATIONS.map((v) => v.cell), []);

  return (
    <>
      <PageHeader title="Pantau pelanggaran" subtitle={`Indikasi aktivitas di sekitar terumbu karang · ${REGION}`} />
      <div className="flex justify-end">
        <ButtonLink href="/dashboard" variant="secondary" className="w-[226px]">
          Kembali ke Dashboard
        </ButtonLink>
      </div>
      <div className="grid grid-cols-[minmax(0,1fr)_372px] items-start gap-5">
        <HeatmapMap
          cells={cells}
          closed={REEF_CELLS}
          flagged={flagged}
          selected={selected ? [selected.cell] : []}
          markers={markers}
          trails={trails}
          title="Pemantauan terumbu karang"
          subtitle={`Aktivitas simulasi · ${VIOLATIONS[0].updatedAt} WIB`}
          legend={[{ label: "Area terumbu", color: LEGEND.closed.color }, LEGEND.flag, { label: "Jejak pergerakan", color: "#48676a" }]}
          height={570}
        />
        <Card className="flex min-h-[570px] flex-col gap-4">
          <h2 className="t-title-m">Daftar nelayan</h2>
          <p className="t-body text-ink-2">{VIOLATIONS.length} indikasi di sekitar terumbu karang</p>
          <ul className="flex flex-col gap-4">
            {VIOLATIONS.map((v) => {
              const active = v.id === selectedId;
              return (
                <li key={v.id}>
                  <button
                    type="button"
                    aria-pressed={active}
                    onClick={() => select(active ? undefined : v.id)}
                    className={`flex w-full flex-col gap-[6px] rounded-[14px] p-[14px] text-left text-ink-2 ${
                      active ? "border-[1.5px] border-error bg-error-bg" : "border border-subtle bg-subtle hover:border-line"
                    }`}
                  >
                    <span className="t-body">
                      {v.fisher} · {PATTERN[v.pattern].short}
                    </span>
                    <span className="t-caption">
                      {v.pattern === "linger" ? `${v.minutes} menit` : `${v.laps} putaran`} · {v.distanceM} m · {v.cell}
                    </span>
                    {sent[v.id] && <span className="t-caption text-success">Peringatan terkirim</span>}
                  </button>
                </li>
              );
            })}
          </ul>
        </Card>
      </div>
      {selected && (
        <Detail
          v={selected}
          sentAt={sent[selected.id]}
          onSend={() => setSent((s) => ({ ...s, [selected.id]: selected.updatedAt }))}
          onClose={() => select()}
        />
      )}
    </>
  );
}

function Detail({ v, sentAt, onSend, onClose }: { v: Violation; sentAt?: string; onSend: () => void; onClose: () => void }) {
  const p = PATTERN[v.pattern];
  return (
    <Card className="flex flex-col gap-4" aria-label={`Detail ${v.fisher}`}>
      <div className="flex gap-4">
        <div className="flex w-[332px] shrink-0 flex-col gap-4">
          <p className={`rounded-[14px] p-[10px] t-caption ${sentAt ? "bg-success-bg text-success" : "bg-error-bg text-error"}`}>
            {sentAt ? "PERINGATAN TERKIRIM" : "INDIKASI AKTIF"}
          </p>
          <h2 className="t-title-m">{v.fisher}</h2>
          <p className="t-body text-ink-2">Grid {v.cell} · Area rehab terumbu</p>
          <div className="flex flex-col gap-[6px] rounded-[14px] bg-error-bg p-[14px] t-body">
            <p className="text-error">{p.title}</p>
            <p className="text-ink-2">
              {v.pattern === "linger"
                ? `Berada di sekitar area rehab selama ${v.minutes} menit.`
                : `Berputar ${v.laps} kali di sekitar area rehab dalam ${v.minutes} menit.`}
            </p>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1 rounded-[14px] bg-subtle p-3">
              <p className="t-caption text-ink-2">{v.pattern === "linger" ? "Durasi" : "Putaran"}</p>
              <p className="t-title-m">{v.pattern === "linger" ? `${v.minutes} menit` : `${v.laps} kali`}</p>
            </div>
            <div className="flex flex-col gap-1 rounded-[14px] bg-subtle p-3">
              <p className="t-caption text-ink-2">Jarak ke terumbu</p>
              <p className="t-title-m">{v.distanceM} m</p>
            </div>
          </div>
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-4">
          <p className="t-body text-ink-2">
            Aktivitas: {p.activity}. Pembaruan terakhir {v.updatedAt} WIB.
          </p>
          <h3 className="t-title-m">Peringatan untuk nelayan</h3>
          <div className="flex flex-col gap-2 rounded-[14px] bg-subtle p-4 text-ink-2">
            <p className="t-caption">REEFISH · PERINGATAN AREA</p>
            <p className="t-body">Segera jauhi terumbu karang</p>
            <p className="t-body">
              Anda mendekati area terumbu karang {v.cell}. Segera menjauh dan arahkan kapal keluar dari area rehab untuk
              menghindari kerusakan karang.
            </p>
          </div>
          {sentAt ? (
            <>
              <p className="flex min-h-12 items-center justify-center rounded-3xl bg-success-bg t-label text-success" role="status">
                Peringatan terkirim
              </p>
              <p className="t-caption text-ink-2">Peringatan berhasil dikirim · {sentAt} WIB</p>
            </>
          ) : (
            <Button onClick={onSend}>Kirim peringatan</Button>
          )}
        </div>
      </div>
      <Button variant="secondary" onClick={onClose}>
        Tutup detail
      </Button>
    </Card>
  );
}
