"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card, Divider, Notice } from "@/components/ui/card";
import { HeatmapMap } from "@/features/geo/components/heatmap-map";
import { HEATMAP, heatCell } from "@/features/geo/mock-heatmap";
import { announcement, fmtDate, KIND_LABEL, KIND_TITLE, NOTICE } from "../format";
import { isExpired, saveDecision, today, type Decision } from "../services/store";
import { NotFound } from "./edit-decision";
import { RevokeForm } from "./revoke-form";
import { useDecision } from "./use-decision";

const STATUS_NOTICE = {
  terbit: { tone: "success", text: "Keputusan terbit · paket nelayan diperbarui" },
  draf: { tone: "info", text: "Draf tersimpan · belum terlihat oleh nelayan" },
  dicabut: { tone: "error", text: "Keputusan dicabut · status grid diperbarui" },
  berakhir: { tone: "warning", text: "Masa berlaku berakhir · grid kembali normal" },
} as const;

export function DecisionDetail({ id, action, notice }: { id: string; action?: string; notice?: string }) {
  const d = useDecision(id);
  if (!d) return <NotFound />;
  if (action === "cabut" && d.status === "terbit" && !isExpired(d)) return <RevokeForm decision={d} />;
  return <Detail d={d} notice={notice} />;
}

function Detail({ d, notice }: { d: Decision; notice?: string }) {
  const router = useRouter();
  const [copied, setCopied] = useState(false);
  const status = isExpired(d) ? "berakhir" : d.status;
  const cs = d.cells.map(heatCell).filter((c) => !!c);
  const fishers = Math.max(0, ...cs.map((c) => c.fishers));
  const trips = cs.reduce((s, c) => s + c.trips, 0);
  const hours = cs.reduce((s, c) => s + c.hours, 0);
  const text = announcement(d);
  const sn = STATUS_NOTICE[status];

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }

  function publish() {
    saveDecision({ ...d, status: "terbit", history: [...d.history, { at: today(), text: "Terbit · tercatat pada audit keputusan" }] });
    router.push("/dashboard?notice=dibuat");
  }

  return (
    <>
      <PageHeader
        title="Keputusan kawasan"
        subtitle={`${d.code} · ${KIND_LABEL[d.kind]} · status ${status}`}
        badge={copied ? "Pengumuman tersalin" : notice && NOTICE[notice] ? NOTICE[notice] : "DATA SIMULASI"}
        badgeTone={copied || (notice && NOTICE[notice]) ? "success" : "info"}
      />
      <div className="grid grid-cols-[minmax(0,720px)_412px] items-start gap-5">
        <Card className="flex flex-col gap-5 p-6">
          <Notice tone={sn.tone} className="w-fit px-4 py-[14px] t-label">
            {sn.text}
          </Notice>
          <h2 className="t-title-m">
            {KIND_TITLE[d.kind]} {d.code}
          </h2>
          <p className="t-body text-ink-2">Alasan: {d.reason || "belum diisi"}</p>
          {d.kind === "kuota" && <p className="t-body text-ink-2">Kuota tangkap: {d.quotaKg} kg per bulan.</p>}
          <p className="t-body text-ink-2">
            {d.reopenCriteria ? `Buka kembali setelah: ${d.reopenCriteria}` : "Kriteria buka kembali belum diisi."}
          </p>
          {d.revoke && (
            <p className="t-body text-ink-2">
              Dicabut efektif {fmtDate(d.revoke.date)}: {d.revoke.reason}
            </p>
          )}
          <Divider />
          <h3 className="t-label">Riwayat status</h3>
          <ol className="flex flex-col gap-5">
            {d.history.map((h, i) => (
              <li key={i} className="t-body text-ink-2">
                {fmtDate(h.at)} · {h.text}
              </li>
            ))}
            {status === "terbit" && (
              <li className="t-body text-ink-2">Berakhir sesuai tanggal keputusan atau dapat dicabut dengan alasan.</li>
            )}
          </ol>
          <h3 className="t-label">Bukti yang terlampir</h3>
          <div className="[&>div]:rounded-[14px]">
            <HeatmapMap cells={HEATMAP} closed={d.cells} selected={d.cells} fitSelected title={`Grid ${d.code}`} height={240} />
          </div>
          <div className="flex flex-col gap-2 rounded-2xl bg-subtle px-4 py-[13px] t-body text-ink-2">
            <p>
              {fishers} nelayan unik · {trips} trip · {hours} jam pada 4 minggu tertutup
            </p>
            <p>
              Lapisan: trip tercatat · Grid {d.code} ({d.cells.length} sel) · data simulasi
            </p>
            <p>Stres panas NOAA: {cs[0]?.heatStress ?? "—"} · dekat lokasi rehab</p>
          </div>
        </Card>

        <div className="flex min-h-[843px] flex-col justify-between gap-5">
          <Card className="flex min-h-[640px] flex-col justify-between gap-6 px-5 py-6">
            <div className="flex flex-col gap-3">
              <h2 className="t-title-m">Pengumuman untuk nelayan</h2>
              <p className="min-h-[254px] rounded-2xl bg-subtle px-4 py-[18px] t-body text-ink">{text}</p>
              <p className="t-body text-ink-2">Teks ini bisa disalin untuk grup KUB atau papan dermaga.</p>
            </div>
            <div className="flex flex-col gap-3">
              {copied ? (
                <Button variant="success" onClick={copy} aria-live="polite">
                  Pengumuman tersalin
                </Button>
              ) : (
                <Button onClick={copy}>Salin pengumuman</Button>
              )}
              {status === "terbit" && (
                <ButtonLink href={`/area/${d.id}?aksi=cabut`} variant="secondary">
                  Cabut keputusan
                </ButtonLink>
              )}
              {status === "draf" && (
                <>
                  <Button variant="secondary" onClick={publish}>
                    Terbitkan keputusan
                  </Button>
                  <ButtonLink href={`/area/${d.id}/edit`} variant="secondary">
                    Edit draf
                  </ButtonLink>
                </>
              )}
            </div>
          </Card>
          <div className="flex flex-col gap-3">
            <ButtonLink href="/dashboard" variant="secondary">
              Kembali ke Dashboard
            </ButtonLink>
            <ButtonLink href="/area" variant="secondary">
              Kelola keputusan
            </ButtonLink>
          </div>
        </div>
      </div>
    </>
  );
}
