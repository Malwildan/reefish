import type { Decision, DecisionKind } from "./services/store";

export const KIND_LABEL: Record<DecisionKind, string> = {
  tutup: "Tutup sementara",
  kuota: "Batasi kuota",
};

// Title used in lists, e.g. "Penutupan sementara".
export const KIND_TITLE: Record<DecisionKind, string> = {
  tutup: "Penutupan sementara",
  kuota: "Pembatasan kuota",
};

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];

export function fmtDate(iso: string) {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-").map(Number);
  return `${d} ${MONTHS[m - 1]} ${y}`;
}

// "16–30 Okt 2026", or full dates when month/year differ.
export function fmtRange(start: string, end: string) {
  if (!start || !end) return fmtDate(start || end);
  const [ys, ms, ds] = start.split("-").map(Number);
  const [ye, me, de] = end.split("-").map(Number);
  if (ys === ye && ms === me) return `${ds}–${de} ${MONTHS[me - 1]} ${ye}`;
  return `${fmtDate(start)} – ${fmtDate(end)}`;
}

export type ShownStatus = Decision["status"] | "berakhir";

export const STATUS_LABEL: Record<ShownStatus, string> = {
  draf: "Draf",
  terbit: "Terbit",
  dicabut: "Dicabut",
  berakhir: "Berakhir",
};

export function announcement(d: Decision) {
  if (d.status === "dicabut") {
    return `Grid ${d.code} dibuka kembali mulai ${fmtDate(d.revoke?.date ?? "")} setelah evaluasi kawasan. Tetap hindari jangkar di atas karang dan cek peta Reefish sebelum berangkat.`;
  }
  if (d.kind === "kuota") {
    return `Grid ${d.code} dibatasi kuota ${d.quotaKg ?? "—"} kg per bulan (${fmtRange(d.start, d.end)}) untuk menjaga area karang. Catat tangkapan di Reefish dan lihat sisa kuota sebelum berangkat.`;
  }
  return `Grid ${d.code} ditutup sementara untuk membantu pemulihan area karang. Hindari penangkapan dan jangkar di grid ini. Lihat batas area pada peta Reefish sebelum berangkat.`;
}

export const NOTICE: Record<string, string> = {
  dibuat: "Keputusan berhasil dibuat",
  draf: "Draf keputusan tersimpan",
  disimpan: "Perubahan berhasil disimpan",
  dihapus: "Keputusan berhasil dihapus",
  dicabut: "Keputusan berhasil dicabut",
};
