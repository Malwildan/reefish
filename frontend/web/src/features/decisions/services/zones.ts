// Mock of the admin zone RPCs (contracts/map-zones-api.openapi.yaml): api_admin_preview_zone,
// api_admin_create_zone, api_admin_list_zones, api_admin_zone_detail, api_admin_edit_zone,
// api_admin_edit_zone_status, api_admin_zone_history. Same inputs, outputs and error codes.
// shortcut: browser localStorage, one simulated admin; swap each function for supabase.rpc(...) later.
import { HEATMAP, heatCell } from "../../geo/mock-heatmap.ts";
import { VIOLATIONS } from "../../violations/mock.ts";
import { validateCreate, validateEdit, validateReason, validateRules } from "../schemas.ts";
import {
  ApiError,
  type Conflict,
  type CreateZoneInput,
  type EditStatusInput,
  type EditZoneInput,
  type ZoneAggregate,
  type ZoneDetail,
  type ZoneDetailWithAggregate,
  type ZoneHistoryAction,
  type ZoneHistoryItem,
  type ZonePreview,
  type ZoneQuota,
  type ZoneRules,
  type ZoneStatus,
  type ZoneSummary,
} from "../types.ts";

type State = { zones: ZoneDetail[]; history: ZoneHistoryItem[]; seq: number };

const KEY = "reefish.zones.v1";
const ADMIN = { id: "demo-admin", name: "Admin Kawasan (demo)" };
export const config = { latencyMs: 250 };

let state: State | null = null;
let version = 0;
const listeners = new Set<() => void>();

const nowIso = () => new Date().toISOString();
const daysAgo = (n: number) => new Date(Date.now() - n * 86400000).toISOString();

function seed(): State {
  const s: State = { zones: [], history: [], seq: 0 };
  const add = (z: Omit<ZoneDetail, "version" | "updated_at">) => {
    s.zones.push({ ...z, version: 1, updated_at: z.created_at });
    s.history.push(hist(s, z.id, z.name, "create", null, { status: z.status, grid_ids: z.grid_ids }, z.reason, z.created_at));
  };
  add({
    id: "zona-karang-sempu",
    name: "Karang Selatan Sempu",
    status: "rehab",
    rules: null,
    reason: "Tutupan karang turun dan fatigue kritis di sekitar terumbu.",
    note: "Hasil rapat pengelola kawasan dan KUB Sendang Biru.",
    effective_from: daysAgo(10),
    effective_until: null,
    grid_ids: ["X099_Y148", "X100_Y148", "X100_Y147"],
    is_active: true,
    archived_at: null,
    created_at: daysAgo(10),
  });
  add({
    id: "zona-kuota-timur",
    name: "Kuota Perairan Timur",
    status: "restricted",
    rules: { max_catch_kg_per_period: 900, max_trips_per_period: 80, period: "monthly", open_schedule: null },
    reason: "Tekanan tangkap tinggi; dibatasi kuota agar stok pulih.",
    note: null,
    effective_from: daysAgo(6),
    effective_until: null,
    grid_ids: ["X103_Y145", "X104_Y145", "X103_Y146", "X104_Y146"],
    is_active: true,
    archived_at: null,
    created_at: daysAgo(6),
  });
  add({
    id: "zona-uji-barat",
    name: "Penutupan Barat (uji)",
    status: "rehab",
    rules: null,
    reason: "Uji coba penutupan selama musim pemijahan.",
    note: null,
    effective_from: daysAgo(40),
    effective_until: null,
    grid_ids: ["X093_Y142", "X094_Y142"],
    is_active: true,
    archived_at: null,
    created_at: daysAgo(40),
  });
  // the third zone was later returned to normal
  const z = s.zones[2];
  z.is_active = false;
  z.archived_at = daysAgo(5);
  z.version = 2;
  z.updated_at = z.archived_at;
  s.history.push(hist(s, z.id, z.name, "update_status", { status: "rehab" }, { status: "normal" }, "Musim pemijahan selesai; evaluasi menunjukkan stok pulih.", z.archived_at));
  s.history.push(hist(s, z.id, z.name, "archive", null, { released_grid_ids: z.grid_ids }, null, z.archived_at));
  return s;
}

function hist(
  s: State,
  zoneId: string,
  zoneName: string,
  action: ZoneHistoryAction,
  before: ZoneHistoryItem["before"],
  after: ZoneHistoryItem["after"],
  reason: string | null,
  at = nowIso(),
): ZoneHistoryItem {
  return { id: ++s.seq, zone_id: zoneId, zone_name: zoneName, action, before, after, reason, changed_by: ADMIN, changed_at: at };
}

function load(): State {
  if (state) return state;
  try {
    const raw = globalThis.localStorage?.getItem(KEY);
    state = raw ? (JSON.parse(raw) as State) : seed();
  } catch {
    state = seed();
  }
  return state;
}

function commit() {
  version++;
  try {
    globalThis.localStorage?.setItem(KEY, JSON.stringify(state));
  } catch {}
  listeners.forEach((l) => l());
}

export function subscribe(l: () => void) {
  listeners.add(l);
  return () => void listeners.delete(l);
}
export const getVersion = () => version;

export async function resetDemo() {
  state = seed();
  commit();
}

const wait = () => new Promise((r) => setTimeout(r, config.latencyMs));
const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));

function fail(code: string, hint: string, details?: Record<string, unknown>): never {
  throw new ApiError(code, hint, details);
}

function failFields(fields: Record<string, string | undefined>) {
  const f = Object.fromEntries(Object.entries(fields).filter(([, v]) => v));
  if (Object.keys(f).length) fail("VALIDATION_ERROR", "Periksa kembali isian.", { fields: f });
}

function activeZoneByGrid(s: State) {
  const m = new Map<string, ZoneDetail>();
  for (const z of s.zones) if (z.is_active) for (const g of z.grid_ids) m.set(g, z);
  return m;
}

// api_heatmap auto_flag: a normal cell (no active zone) whose fatigue is critical is flagged
// restricted by the system and waits for an admin decision.
function autoFlagged(s: State) {
  const zones = activeZoneByGrid(s);
  return new Set(HEATMAP.filter((c) => c.fatigueLevel === "critical" && !zones.has(c.id)).map((c) => c.id));
}

function periodBounds(period: ZoneRules["period"], now = new Date()) {
  // WIB = UTC+7: weekly starts Monday 00:00 WIB, monthly on the 1st (contract ZoneRules.period)
  const wib = new Date(now.getTime() + 7 * 3600000);
  const start = new Date(Date.UTC(wib.getUTCFullYear(), wib.getUTCMonth(), period === "monthly" ? 1 : wib.getUTCDate()));
  if (period === "weekly") start.setUTCDate(start.getUTCDate() - ((start.getUTCDay() + 6) % 7));
  const end = new Date(start);
  if (period === "monthly") end.setUTCMonth(end.getUTCMonth() + 1);
  else end.setUTCDate(end.getUTCDate() + 7);
  const toUtc = (d: Date) => new Date(d.getTime() - 7 * 3600000).toISOString();
  return { start: toUtc(start), end: toUtc(end), fraction: period === "monthly" ? 1 : 7 / 30 };
}

function aggregate(s: State, gridIds: string[], zone?: ZoneDetail): ZoneAggregate {
  const zones = activeZoneByGrid(s);
  const cells = gridIds.map(heatCell).filter((c) => !!c);
  const sum = (f: (c: (typeof cells)[number]) => number) => cells.reduce((t, c) => t + f(c), 0);
  const fatigues = cells.map((c) => c.fatigue);
  const catchKg = sum((c) => c.catchKg);
  const trips = sum((c) => c.trips);
  const hours = sum((c) => c.hours);
  let quota: ZoneQuota | null = null;
  if (zone?.status === "restricted" && zone.rules) {
    const b = periodBounds(zone.rules.period);
    const usedKg = Math.round(catchKg * b.fraction);
    const usedTrips = Math.round(trips * b.fraction);
    const remKg = zone.rules.max_catch_kg_per_period == null ? null : zone.rules.max_catch_kg_per_period - usedKg;
    const remTrips = zone.rules.max_trips_per_period == null ? null : zone.rules.max_trips_per_period - usedTrips;
    quota = {
      period_start: b.start,
      period_end: b.end,
      used_kg: usedKg,
      used_trips: usedTrips,
      remaining_kg: remKg == null ? null : Math.max(0, remKg),
      remaining_trips: remTrips == null ? null : Math.max(0, remTrips),
      exhausted: (remKg != null && remKg <= 0) || (remTrips != null && remTrips <= 0),
    };
  }
  return {
    grid_count: gridIds.length,
    area_km2: Math.round(gridIds.length * 0.25 * 100) / 100,
    coral_grid_count: cells.filter((c) => c.hasCoral).length,
    coral_pct: gridIds.length ? Math.round((cells.filter((c) => c.hasCoral).length / gridIds.length) * 1000) / 10 : null,
    fatigue_avg: fatigues.length ? Math.round((fatigues.reduce((a, b) => a + b, 0) / fatigues.length) * 100) / 100 : null,
    fatigue_max: fatigues.length ? Math.max(...fatigues) : null,
    fatigue_distribution: {
      healthy: cells.filter((c) => c.fatigueLevel === "healthy").length,
      tired: cells.filter((c) => c.fatigueLevel === "tired").length,
      critical: cells.filter((c) => c.fatigueLevel === "critical").length,
    },
    // auto_flag only exists on cells outside an active zone
    flagged_grid_count: cells.filter((c) => c.fatigueLevel === "critical" && !zones.has(c.id)).length,
    trip_count_30d: trips,
    catch_kg_30d: catchKg,
    fishing_hours_30d: hours,
    cpue_30d: hours ? Math.round((catchKg / hours) * 10) / 10 : null,
    violation_count_30d: VIOLATIONS.filter((v) => gridIds.includes(v.cell)).length,
    quota,
  };
}

function summary(s: State, z: ZoneDetail): ZoneSummary {
  const a = aggregate(s, z.grid_ids, z);
  return {
    id: z.id,
    name: z.name,
    status: z.status,
    effective_from: z.effective_from,
    effective_until: z.effective_until,
    is_active: z.is_active,
    archived_at: z.archived_at,
    updated_at: z.updated_at,
    grid_count: a.grid_count,
    area_km2: a.area_km2,
    fatigue_avg: a.fatigue_avg,
    fatigue_max: a.fatigue_max,
    quota_remaining_kg: a.quota?.remaining_kg ?? null,
    quota_exhausted: a.quota?.exhausted ?? false,
  };
}

function find(s: State, id: string) {
  return s.zones.find((z) => z.id === id) ?? fail("ZONE_NOT_FOUND", "Zona tidak ditemukan.");
}

/** api_admin_preview_zone: aggregate for a selection plus cells already held by an active zone. */
export async function previewZone(gridIds: string[]): Promise<ZonePreview> {
  await wait();
  const s = load();
  if (!gridIds.length) fail("ZONE_EMPTY", "Pilih minimal satu grid.");
  const ids = [...new Set(gridIds)];
  const invalid = ids.filter((g) => !heatCell(g));
  const valid = ids.filter((g) => heatCell(g));
  const zones = activeZoneByGrid(s);
  const conflicts: Conflict[] = valid
    .filter((g) => zones.has(g))
    .map((g) => ({ grid_id: g, zone_id: zones.get(g)!.id, zone_name: zones.get(g)!.name, zone_status: zones.get(g)!.status }));
  const flags = autoFlagged(s);
  // rehab cells can never join the new zone, so they are left out of its aggregate
  const inZone = valid.filter((g) => zones.get(g)?.status !== "rehab");
  return { aggregate: aggregate(s, inZone), conflicts, invalid_grid_ids: invalid, auto_flagged_grid_ids: inZone.filter((g) => flags.has(g)) };
}

/**
 * api_admin_create_zone. on_conflict "move" takes cells out of restricted zones (a zone left
 * without cells is archived); cells of a rehab zone are never moved: zero tolerance, decided there.
 */
export async function createZone(p: CreateZoneInput): Promise<ZoneDetailWithAggregate> {
  await wait();
  const s = load();
  const errs = validateCreate(p);
  if (errs.rules) fail("RULES_REQUIRED", errs.rules);
  failFields(errs);
  const ids = [...new Set(p.grid_ids)];
  const invalid = ids.filter((g) => !heatCell(g));
  if (invalid.length) fail("GRID_INVALID", "Ada grid yang tidak dikenal.", { grid_ids: invalid });
  const name = p.name.trim();
  if (s.zones.some((z) => z.is_active && z.name.toLowerCase() === name.toLowerCase()))
    fail("ZONE_NAME_TAKEN", "Nama zona sudah dipakai zona aktif lain.");
  const zones = activeZoneByGrid(s);
  const conflicts = ids
    .filter((g) => zones.has(g))
    .map((g) => ({ grid_id: g, zone_id: zones.get(g)!.id, zone_name: zones.get(g)!.name, zone_status: zones.get(g)!.status }));
  const blocked = p.on_conflict === "move" ? conflicts.filter((c) => c.zone_status === "rehab") : conflicts;
  if (blocked.length) fail("GRID_CONFLICT", "Sebagian grid sudah masuk zona aktif lain.", { conflicts: blocked });

  const at = nowIso();
  const name0 = name;
  for (const src of new Set(conflicts.map((c) => zones.get(c.grid_id)!))) {
    const moved = src.grid_ids.filter((g) => ids.includes(g));
    src.grid_ids = src.grid_ids.filter((g) => !ids.includes(g));
    src.version++;
    src.updated_at = at;
    s.history.push(hist(s, src.id, src.name, "remove_grids", { grid_ids: moved }, { moved_to: name0 }, `Dipindah ke zona "${name0}"`, at));
    if (!src.grid_ids.length) {
      src.is_active = false;
      src.archived_at = at;
      s.history.push(hist(s, src.id, src.name, "archive", null, { released_grid_ids: [] }, "Semua grid dipindah ke zona lain", at));
    }
  }
  const z: ZoneDetail = {
    id: crypto.randomUUID(),
    name,
    status: p.status,
    rules: p.status === "restricted" ? p.rules : null,
    reason: p.reason.trim(),
    note: p.note?.trim() || null,
    effective_from: p.effective_from ?? at,
    effective_until: p.effective_until,
    grid_ids: ids,
    is_active: true,
    archived_at: null,
    version: 1,
    created_at: at,
    updated_at: at,
  };
  s.zones.push(z);
  s.history.push(hist(s, z.id, z.name, "create", null, { status: z.status, grid_ids: ids, rules: z.rules }, z.reason, at));
  commit();
  return clone({ ...z, aggregate: aggregate(s, z.grid_ids, z) });
}

/** api_admin_list_zones */
export async function listZones(opts: { status?: ZoneStatus; includeArchived?: boolean } = {}): Promise<ZoneSummary[]> {
  await wait();
  const s = load();
  return s.zones
    .filter((z) => (opts.includeArchived || z.is_active) && (!opts.status || z.status === opts.status))
    .sort((a, b) => b.updated_at.localeCompare(a.updated_at))
    .map((z) => summary(s, z));
}

/** Cells auto-flagged restricted by the system (api_heatmap auto_flag). */
export async function autoFlaggedGrids(): Promise<string[]> {
  await wait();
  return [...autoFlagged(load())];
}

/** Zone per grid for the map (the zone_id column of api_heatmap). */
export async function zoneGridIndex(): Promise<Record<string, { id: string; name: string; status: ZoneStatus }>> {
  await wait();
  const out: Record<string, { id: string; name: string; status: ZoneStatus }> = {};
  for (const [g, z] of activeZoneByGrid(load())) out[g] = { id: z.id, name: z.name, status: z.status };
  return out;
}

/** api_admin_zone_detail (+ aggregate). Archived zones can still be opened. */
export async function zoneDetail(id: string): Promise<ZoneDetailWithAggregate> {
  await wait();
  const s = load();
  const z = find(s, id);
  return clone({ ...z, aggregate: aggregate(s, z.grid_ids, z) });
}

/** api_admin_zone_history; without an id it returns every zone's history (decision history page). */
export async function zoneHistory(id?: string): Promise<ZoneHistoryItem[]> {
  await wait();
  const s = load();
  return clone(s.history.filter((h) => !id || h.zone_id === id).sort((a, b) => b.changed_at.localeCompare(a.changed_at) || b.id - a.id));
}

/** api_admin_edit_zone: metadata and rules only. */
export async function editZone(id: string, p: EditZoneInput): Promise<ZoneDetailWithAggregate> {
  await wait();
  const s = load();
  const z = find(s, id);
  if (!z.is_active) fail("ZONE_ARCHIVED", "Zona sudah kembali normal dan tidak bisa diubah.");
  if (p.version !== z.version) fail("VERSION_CONFLICT", "Zona sudah diubah orang lain. Muat ulang halaman.", { current_version: z.version });
  const errs = validateEdit(p, z.status);
  if (errs.rules) fail("RULES_REQUIRED", errs.rules);
  failFields(errs);
  if (p.name && s.zones.some((o) => o.id !== z.id && o.is_active && o.name.toLowerCase() === p.name!.trim().toLowerCase()))
    fail("ZONE_NAME_TAKEN", "Nama zona sudah dipakai zona aktif lain.");

  const before = { name: z.name, rules: z.rules, effective_from: z.effective_from, effective_until: z.effective_until, note: z.note };
  const rulesChanged = p.rules !== undefined && JSON.stringify(p.rules) !== JSON.stringify(z.rules);
  if (p.name !== undefined) z.name = p.name.trim();
  if (p.rules !== undefined && z.status === "restricted") z.rules = p.rules;
  if (p.effective_from) z.effective_from = p.effective_from;
  if (p.effective_until !== undefined) z.effective_until = p.effective_until;
  if (p.note !== undefined) z.note = p.note?.trim() || null;
  z.version++;
  z.updated_at = nowIso();
  const after = { name: z.name, rules: z.rules, effective_from: z.effective_from, effective_until: z.effective_until, note: z.note };
  s.history.push(hist(s, z.id, z.name, rulesChanged ? "update_rules" : "update_meta", before, after, p.reason.trim()));
  commit();
  return clone({ ...z, aggregate: aggregate(s, z.grid_ids, z) });
}

/** api_admin_edit_zone_status. `normal` archives the zone and releases its grids. */
export async function editZoneStatus(id: string, p: EditStatusInput): Promise<ZoneDetailWithAggregate> {
  await wait();
  const s = load();
  const z = find(s, id);
  if (!z.is_active) fail("ZONE_ARCHIVED", "Zona sudah kembali normal.");
  if (p.version !== z.version) fail("VERSION_CONFLICT", "Zona sudah diubah orang lain. Muat ulang halaman.", { current_version: z.version });
  if (p.status === z.status) fail("SAME_STATUS", "Status zona sudah sama.");
  failFields(validateReason(p.reason));
  if (p.status === "restricted") {
    const errs = validateRules("restricted", p.rules);
    if (errs.rules) fail("RULES_REQUIRED", errs.rules);
    failFields(errs);
  }
  const at = nowIso();
  const before = { status: z.status, rules: z.rules };
  if (p.status === "normal") {
    z.is_active = false;
    z.archived_at = at;
  } else {
    z.status = p.status;
    z.rules = p.status === "restricted" ? p.rules! : null;
  }
  z.version++;
  z.updated_at = at;
  s.history.push(hist(s, z.id, z.name, "update_status", before, { status: p.status, rules: z.rules }, p.reason.trim(), at));
  if (p.status === "normal") s.history.push(hist(s, z.id, z.name, "archive", null, { released_grid_ids: z.grid_ids }, null, at));
  commit();
  return clone({ ...z, aggregate: aggregate(s, z.grid_ids, z) });
}

