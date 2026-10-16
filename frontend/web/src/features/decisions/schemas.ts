import type { CreateZoneInput, EditZoneInput, ZoneRules, ZoneStatus } from "./types.ts";

// Same rules as api_admin_create_zone / api_admin_edit_zone. Used by the form (instant feedback)
// before calling the RPC; the SQL functions check again and stay the authority.
export type FieldErrors = Partial<Record<string, string>>;

export function validateRules(status: ZoneStatus, rules: ZoneRules | null | undefined): FieldErrors {
  const e: FieldErrors = {};
  if (status !== "restricted") return e;
  const kg = rules?.max_catch_kg_per_period;
  const trips = rules?.max_trips_per_period;
  if (kg == null && trips == null) e.rules = "Zona restricted wajib punya batas tangkapan (kg) atau batas trip.";
  if (kg != null && !(kg > 0)) e.max_catch_kg_per_period = "Batas tangkapan harus lebih dari 0 kg.";
  if (trips != null && !(Number.isInteger(trips) && trips > 0)) e.max_trips_per_period = "Batas trip harus bilangan bulat > 0.";
  if (!rules?.period) e.period = "Pilih periode kuota.";
  const sch = rules?.open_schedule;
  if (sch) {
    if (!sch.days.length) e.open_schedule = "Pilih minimal satu hari buka.";
    else if (!/^\d{2}:\d{2}$/.test(sch.hours[0]) || !/^\d{2}:\d{2}$/.test(sch.hours[1]) || sch.hours[0] >= sch.hours[1])
      e.open_schedule = "Jam buka harus HH:mm dan jam mulai sebelum jam selesai.";
  }
  return e;
}

function validateMeta(p: Partial<CreateZoneInput>): FieldErrors {
  const e: FieldErrors = {};
  if (p.name !== undefined) {
    const n = p.name.trim().length;
    if (n < 3 || n > 100) e.name = "Nama zona 3–100 karakter.";
  }
  if (p.note && p.note.length > 2000) e.note = "Catatan maksimal 2000 karakter.";
  if (p.effective_from && p.effective_until && p.effective_until <= p.effective_from)
    e.effective_until = "Tanggal berakhir harus setelah tanggal mulai.";
  return e;
}

export function validateReason(reason: string): FieldErrors {
  const n = reason.trim().length;
  return n < 3 || n > 500 ? { reason: "Alasan wajib diisi (3–500 karakter)." } : {};
}

export function validateCreate(p: CreateZoneInput): FieldErrors {
  return {
    ...validateMeta(p),
    ...validateReason(p.reason),
    ...validateRules(p.status, p.rules),
    ...(p.grid_ids.length ? {} : { grid_ids: "Pilih minimal satu grid." }),
    ...(p.grid_ids.length > 5000 ? { grid_ids: "Maksimal 5000 grid per zona." } : {}),
  };
}

export function validateEdit(p: EditZoneInput, status: ZoneStatus): FieldErrors {
  return {
    ...validateMeta(p),
    ...validateReason(p.reason),
    ...(p.rules !== undefined ? validateRules(status, p.rules) : {}),
  };
}
