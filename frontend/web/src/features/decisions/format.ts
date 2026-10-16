import type { GridStatus, ZoneHistoryAction, ZoneRules } from "./types";

export const STATUS_LABEL: Record<GridStatus, string> = {
  normal: "Normal",
  restricted: "Restricted",
  rehab: "Rehab",
};

export const STATUS_HINT: Record<GridStatus, string> = {
  normal: "Grid kembali dibuka tanpa batasan.",
  restricted: "Boleh menangkap dengan kuota agregat untuk seluruh grid zona.",
  rehab: "Zero tolerance: semua grid dinonaktifkan untuk penangkapan.",
};

export const STATUS_TONE: Record<GridStatus, "info" | "warning" | "error"> = {
  normal: "info",
  restricted: "warning",
  rehab: "error",
};

export const ACTION_LABEL: Record<ZoneHistoryAction, string> = {
  create: "Keputusan dibuat",
  update_meta: "Data zona diubah",
  update_rules: "Aturan kuota diubah",
  add_grids: "Grid ditambahkan",
  remove_grids: "Grid dipindah ke zona lain",
  update_status: "Status diubah",
  archive: "Grid dilepas",
};

export const PERIOD_LABEL: Record<ZoneRules["period"], string> = { weekly: "per minggu", monthly: "per bulan" };
export const DAY_LABEL = ["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"];

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];

// Dates are shown in WIB, the pilot's local time.
function wib(iso: string) {
  return new Date(new Date(iso).getTime() + 7 * 3600000);
}

export function fmtDate(iso: string | null | undefined) {
  if (!iso) return "—";
  const d = wib(iso);
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

export function fmtDateTime(iso: string | null | undefined) {
  if (!iso) return "—";
  const d = wib(iso);
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mm = String(d.getUTCMinutes()).padStart(2, "0");
  return `${fmtDate(iso)} · ${hh}.${mm} WIB`;
}

export const fmtUntil = (until: string | null) => (until ? `Berlaku s.d. ${fmtDate(until)}` : "Tanpa batas akhir");

export function fmtValidity(from: string, until: string | null) {
  return until ? `${fmtDate(from)} – ${fmtDate(until)}` : `Mulai ${fmtDate(from)} · tanpa batas akhir`;
}

export const num = (v: number | null | undefined, digits = 0) =>
  v == null ? "—" : v.toLocaleString("id-ID", { maximumFractionDigits: digits });

export function rulesText(r: ZoneRules | null) {
  if (!r) return "Tidak ada kuota (zero tolerance)";
  const parts = [
    r.max_catch_kg_per_period != null && `${num(r.max_catch_kg_per_period)} kg`,
    r.max_trips_per_period != null && `${num(r.max_trips_per_period)} trip`,
  ].filter(Boolean);
  const sched = r.open_schedule
    ? ` · buka ${r.open_schedule.days.map((d) => DAY_LABEL[d - 1]).join(", ")} ${r.open_schedule.hours[0]}–${r.open_schedule.hours[1]} WIB`
    : "";
  return `${parts.join(" + ")} ${PERIOD_LABEL[r.period]}${sched}`;
}

// <input type="date"> value <-> ISO date-time at 00:00 WIB.
export const toDateInput = (iso: string | null) => (iso ? wib(iso).toISOString().slice(0, 10) : "");
export const fromDateInput = (v: string) => (v ? new Date(`${v}T00:00:00+07:00`).toISOString() : null);

export const NOTICE: Record<string, string> = {
  dibuat: "Keputusan zona berhasil dibuat",
  disimpan: "Perubahan berhasil disimpan",
  status: "Status zona berhasil diubah",
  normal: "Zona dikembalikan ke normal",
};
