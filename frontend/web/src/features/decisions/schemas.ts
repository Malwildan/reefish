import type { Decision } from "./services/store";

export type DecisionInput = Pick<
  Decision,
  "code" | "kind" | "cells" | "start" | "end" | "reason" | "reopenCriteria" | "meetingDate" | "meetingSummary" | "quotaKg"
>;
export type Errors = Partial<Record<keyof DecisionInput, string>>;

// Mirrors the server rules of api_admin_create_zone (name 3..100, reason required, rules for restricted).
export function validateDecision(v: DecisionInput, publish: boolean): Errors {
  const e: Errors = {};
  if (v.code.trim().length < 3) e.code = "Kode area minimal 3 karakter.";
  if (!v.cells.length) e.cells = "Pilih minimal satu grid di peta.";
  if (!publish) return e; // a draft only needs a name and an area
  if (!v.start) e.start = "Isi tanggal mulai.";
  if (!v.end) e.end = "Isi tanggal selesai.";
  if (v.start && v.end && v.end < v.start) e.end = "Tanggal selesai harus setelah tanggal mulai.";
  if (v.reason.trim().length < 5) e.reason = "Alasan wajib diisi.";
  if (!v.meetingDate) e.meetingDate = "Isi tanggal rapat.";
  if (v.kind === "kuota" && !(Number(v.quotaKg) > 0)) e.quotaKg = "Kuota harus lebih dari 0 kg.";
  return e;
}

export type RevokeInput = NonNullable<Decision["revoke"]>;

export function validateRevoke(v: RevokeInput, publishedOn: string) {
  const e: Partial<Record<keyof RevokeInput, string>> = {};
  if (!v.date) e.date = "Isi tanggal pencabutan.";
  else if (v.date < publishedOn) e.date = "Tidak boleh sebelum tanggal terbit.";
  if (v.reason.trim().length < 5) e.reason = "Alasan pencabutan wajib dicatat.";
  if (!v.meetingDate) e.meetingDate = "Isi tanggal rapat.";
  return e;
}
