"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog } from "@/components/ui/dialog";
import { HeatmapMap } from "@/features/geo/components/heatmap-map";
import { HEATMAP } from "@/features/geo/mock-heatmap";
import { fmtRange, KIND_TITLE, NOTICE, STATUS_LABEL } from "../format";
import { isExpired, removeDecision, useDecisions, type Decision } from "../services/store";

const REGION = "Sendang Biru–CMC";

export function AreaView({ focus, notice }: { focus?: string; notice?: string }) {
  const router = useRouter();
  const decisions = useDecisions();
  const [toDelete, setToDelete] = useState<Decision | null>(null);
  const shown = decisions.find((d) => d.id === focus) ?? decisions[0];

  return (
    <>
      <PageHeader
        title="Area kawasan"
        subtitle={`Pantau batas kawasan dan kelola keputusan area ${REGION}`}
        badge={notice && NOTICE[notice] ? NOTICE[notice] : "DATA SIMULASI"}
        badgeTone={notice && NOTICE[notice] ? "success" : "info"}
      />
      <div className="grid grid-cols-[500px_minmax(0,632px)] items-start gap-5">
        <Card className="flex flex-col gap-4 p-6">
          <h2 className="t-title-m">Peta area</h2>
          <p className="t-body text-ink-2">
            {REGION}
            {shown && ` · Grid ${shown.code}`}
          </p>
          {/* key: remount so the preview zooms to the newly chosen decision */}
          <div className="[&>div]:rounded-[14px]">
            <HeatmapMap
              key={shown?.id ?? "none"}
              cells={HEATMAP}
              closed={shown ? shown.cells : []}
              selected={shown ? shown.cells : []}
              fitSelected
              title={shown ? `Grid ${shown.code}` : "Belum ada area"}
              height={330}
            />
          </div>
          {shown ? (
            <>
              <p className="t-label">
                {shown.code} · {KIND_TITLE[shown.kind]}
              </p>
              <p className="t-body text-ink-2">
                {fmtRange(shown.start, shown.end)} · {shown.reopenCriteria || shown.reason || "Belum ada catatan"}
              </p>
              <ButtonLink href={`/dashboard?grid=${shown.cells[0]}`}>Lihat detail grid</ButtonLink>
            </>
          ) : (
            <p className="t-body text-ink-2">Keputusan yang dibuat akan tampil di peta ini.</p>
          )}
        </Card>

        <Card className="flex flex-col gap-5 p-6">
          <div className="flex min-h-[61px] items-center gap-4">
            <h2 className="flex-1 t-title-m">Keputusan area</h2>
            <ButtonLink href="/area/baru" className="w-[194px]">
              + Buat keputusan
            </ButtonLink>
          </div>
          <p className="t-body text-ink-2">{decisions.length} keputusan · kelola status dan batas area</p>
          {decisions.map((d) => {
            const status = isExpired(d) ? "berakhir" : d.status;
            return (
              <article
                key={d.id}
                className={`flex flex-col gap-3 rounded-2xl p-5 ${d.id === shown?.id ? "bg-subtle ring-1 ring-line" : "bg-subtle/60"}`}
              >
                <button
                  type="button"
                  onClick={() => router.replace(`/area?id=${d.id}`)}
                  className="flex flex-col gap-3 text-left"
                  aria-label={`Tampilkan ${d.code} di peta`}
                >
                  <span className="t-caption uppercase text-ink-2">
                    {STATUS_LABEL[status]} · {d.code}
                  </span>
                  <span className="t-title-m">{KIND_TITLE[d.kind]}</span>
                  <span className="t-label">{fmtRange(d.start, d.end)}</span>
                  <span className="t-body text-ink-2">{d.reason || "Alasan belum diisi"}</span>
                </button>
                <div className="flex min-h-[68px] items-center justify-between gap-3">
                  <ButtonLink href={`/area/${d.id}`} variant="secondary" className="w-[160px]">
                    Lihat
                  </ButtonLink>
                  <ButtonLink
                    href={`/area/${d.id}/edit`}
                    variant="secondary"
                    className={`w-[160px] ${status === "draf" || status === "terbit" ? "" : "pointer-events-none opacity-50"}`}
                    aria-disabled={!(status === "draf" || status === "terbit")}
                  >
                    Edit
                  </ButtonLink>
                  <Button variant="secondary" className="w-[160px]" onClick={() => setToDelete(d)}>
                    Hapus
                  </Button>
                </div>
              </article>
            );
          })}
          <p className="t-body text-ink-2">Keputusan baru dan perubahan yang disimpan akan muncul di Dashboard.</p>
          <ButtonLink href="/dashboard" variant="secondary">
            Kembali ke Dashboard
          </ButtonLink>
        </Card>
      </div>

      <Dialog open={!!toDelete} onClose={() => setToDelete(null)} title="Hapus keputusan ini?">
        {toDelete && (
          <>
            <p className="t-label">
              {toDelete.code} · {KIND_TITLE[toDelete.kind]}
            </p>
            <p className="t-body text-ink-2">
              Keputusan akan dihapus dari daftar area. Tinjau kembali sebelum melanjutkan.
            </p>
            <div className="grid grid-cols-2 gap-4 pt-1">
              <Button variant="secondary" onClick={() => setToDelete(null)} autoFocus>
                Batal
              </Button>
              <Button
                onClick={() => {
                  removeDecision(toDelete.id);
                  setToDelete(null);
                  router.push("/area?notice=dihapus");
                }}
              >
                Hapus keputusan
              </Button>
            </div>
          </>
        )}
      </Dialog>
    </>
  );
}
