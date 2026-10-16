import { createClient, demoEnabled, supabaseEnabled } from "../../../lib/supabase/client.ts";
import { getHeatmapSnapshot, invalidateHeatmapSnapshot } from "../../geo/services/heatmap.ts";
import * as demo from "./demo-zones.ts";
import {
  ApiError,
  type Conflict,
  type CreateZoneInput,
  type EditStatusInput,
  type EditZoneInput,
  type ZoneDetailWithAggregate,
  type ZoneHistoryAction,
  type ZoneHistoryItem,
  type ZonePreview,
  type ZoneStatus,
  type ZoneSummary,
} from "../types.ts";

/** Demo controls stay available for the explicit, unconfigured development experience. */
export const config = demo.config;

type RpcResult<T> = { data: T | null; error: unknown };
type Rpc = (name: string, args?: Record<string, unknown>) => Promise<RpcResult<unknown>>;
let rpcOverride: Rpc | null = null;
let revision = 0;
const listeners = new Set<() => void>();

// A tiny injection seam keeps contract-level RPC tests independent of Supabase accounts.
export function setZoneRpcForTests(rpc: Rpc | null) {
  rpcOverride = rpc;
}

export function subscribe(listener: () => void) {
  listeners.add(listener);
  const unsubscribeDemo = demo.subscribe(listener);
  return () => {
    listeners.delete(listener);
    unsubscribeDemo();
  };
}
export const getVersion = () => revision + demo.getVersion();

function changed() {
  revision++;
  listeners.forEach((listener) => listener());
}

function parseDetails(details: unknown): Record<string, unknown> | undefined {
  if (typeof details === "string") {
    try {
      const value: unknown = JSON.parse(details);
      return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
    } catch {
      return undefined;
    }
  }
  return details && typeof details === "object" && !Array.isArray(details)
    ? details as Record<string, unknown>
    : undefined;
}

function mapRpcError(error: unknown): ApiError {
  const e = error && typeof error === "object" ? error as Record<string, unknown> : {};
  const code = typeof e.message === "string" && e.message !== "" ? e.message
    : typeof e.code === "string" && e.code !== "" ? e.code : "RPC_ERROR";
  const message = typeof e.hint === "string" && e.hint !== "" ? e.hint
    : typeof e.details === "string" && e.details !== "" ? e.details
    : code === "PGRST202" ? "RPC zona tidak tersedia pada backend yang terhubung."
    : "Permintaan zona gagal. Coba muat ulang.";
  return new ApiError(code, message, parseDetails(e.details));
}

function isDemo() {
  if (rpcOverride) return false;
  if (supabaseEnabled) return false;
  if (demoEnabled) return true;
  throw new ApiError("SUPABASE_CONFIG_MISSING", "Konfigurasi Supabase wajib tersedia pada production.");
}

async function call<T>(name: string, args: Record<string, unknown> = {}): Promise<T> {
  if (rpcOverride) {
    const result = await rpcOverride(name, args);
    if (result.error) throw mapRpcError(result.error);
    return result.data as T;
  }
  if (!supabaseEnabled) throw new ApiError("SUPABASE_CONFIG_MISSING", "Konfigurasi Supabase belum tersedia.");
  const { data, error } = await createClient().rpc(name, args);
  if (error) throw mapRpcError(error);
  return data as T;
}

function demoMode() {
  return isDemo();
}

export async function resetDemo() {
  if (!demoMode()) throw new ApiError("DEMO_DISABLED", "Reset data demo hanya tersedia dalam mode demo.");
  await demo.resetDemo();
  changed();
}

type ZoneEntry = { id: string; name: string; status: ZoneStatus; grid_ids: string[] };
type ZonesResponse = { zones: ZoneEntry[]; heatmap_version: number };
async function liveZoneGridIndex(): Promise<Record<string, { id: string; name: string; status: ZoneStatus }>> {
  const result = await call<ZonesResponse>("api_zones", { p_include_outline: false });
  const index: Record<string, { id: string; name: string; status: ZoneStatus }> = {};
  for (const zone of result.zones ?? []) {
    for (const gridId of zone.grid_ids ?? []) index[gridId] = { id: zone.id, name: zone.name, status: zone.status };
  }
  return index;
}

async function liveAutoFlaggedGrids(): Promise<string[]> {
  const snapshot = await getHeatmapSnapshot();
  return snapshot.cells.filter((cell) => cell.autoFlag === "restricted" && !cell.zoneId).map((cell) => cell.id);
}

export async function previewZone(gridIds: string[]): Promise<ZonePreview> {
  if (demoMode()) return demo.previewZone(gridIds);
  const [result, index, flags] = await Promise.all([
    call<Omit<ZonePreview, "auto_flagged_grid_ids"> & { valid_grid_ids: string[] }>("api_admin_preview_zone", {
      p: { grid_ids: gridIds },
    }),
    liveZoneGridIndex(),
    liveAutoFlaggedGrids(),
  ]);
  const conflicts: Conflict[] = (result.conflicts ?? []).map((conflict) => {
    const zone = index[conflict.grid_id];
    if (!zone || zone.id !== conflict.zone_id) {
      throw new ApiError("BACKEND_CONTRACT_ERROR", "Data konflik zona tidak cocok dengan daftar zona aktif.");
    }
    return { ...conflict, zone_status: zone.status };
  });
  const valid = new Set(result.valid_grid_ids ?? []);
  return {
    aggregate: result.aggregate,
    conflicts,
    invalid_grid_ids: result.invalid_grid_ids ?? [],
    auto_flagged_grid_ids: flags.filter((id) => valid.has(id)),
  };
}

export async function createZone(input: CreateZoneInput): Promise<ZoneDetailWithAggregate> {
  if (demoMode()) return demo.createZone(input);
  const data = await call<ZoneDetailWithAggregate>("api_admin_create_zone", { p: input });
  invalidateHeatmapSnapshot();
  changed();
  return data;
}

export async function listZones(options: {
  status?: ZoneStatus;
  includeArchived?: boolean;
  q?: string;
  sort?: "name" | "-fatigue_max" | "-fatigue_avg" | "-grid_count" | "-updated_at" | "-created_at";
  page?: number;
  limit?: number;
} = {}): Promise<ZoneSummary[]> {
  if (demoMode()) return demo.listZones(options);
  const args = {
    p_status: options.status ?? null,
    p_q: options.q ?? null,
    p_sort: options.sort ?? "-updated_at",
    p_page: options.page ?? 1,
    p_limit: options.limit ?? 100,
    p_include_archived: options.includeArchived ?? false,
  };
  const response = await call<{ data: ZoneSummary[]; meta?: { total?: number } }>("api_admin_list_zones", args);
  const rows = response.data ?? [];
  if (options.page != null || options.limit != null || rows.length >= (response.meta?.total ?? rows.length)) return rows;
  const pageCount = Math.ceil((response.meta?.total ?? rows.length) / args.p_limit);
  if (pageCount <= 1) return rows;
  const rest = await Promise.all(Array.from({ length: pageCount - 1 }, (_, i) => call<{ data: ZoneSummary[] }>("api_admin_list_zones", {
    ...args,
    p_page: i + 2,
  })));
  return rows.concat(...rest.map((page) => page.data ?? []));
}

export async function autoFlaggedGrids(): Promise<string[]> {
  if (demoMode()) return demo.autoFlaggedGrids();
  return liveAutoFlaggedGrids();
}

export async function zoneGridIndex(): Promise<Record<string, { id: string; name: string; status: ZoneStatus }>> {
  if (demoMode()) return demo.zoneGridIndex();
  return liveZoneGridIndex();
}

export async function zoneDetail(id: string): Promise<ZoneDetailWithAggregate> {
  if (demoMode()) return demo.zoneDetail(id);
  return call<ZoneDetailWithAggregate>("api_admin_zone_detail", { p_id: id });
}

type HistoryResponse = { data: ZoneHistoryItem[]; meta?: { total?: number; page?: number; limit?: number } };
async function zoneHistoryPages(id: string, name: string, action?: ZoneHistoryAction): Promise<ZoneHistoryItem[]> {
  const first = await call<HistoryResponse>("api_admin_zone_history", {
    p_id: id, p_action: action ?? null, p_page: 1, p_limit: 100,
  });
  const rows = first.data ?? [];
  const total = first.meta?.total ?? rows.length;
  if (rows.length >= total) return rows.map((row) => ({ ...row, zone_id: id, zone_name: name }));
  const pages = Math.ceil(total / 100);
  const rest = await Promise.all(Array.from({ length: pages - 1 }, (_, i) => call<HistoryResponse>("api_admin_zone_history", {
    p_id: id, p_action: action ?? null, p_page: i + 2, p_limit: 100,
  })));
  return rows.concat(...rest.map((page) => page.data ?? []))
    .map((row) => ({ ...row, zone_id: id, zone_name: name }));
}

async function allZoneSummaries(): Promise<ZoneSummary[]> {
  const first = await call<{ data: ZoneSummary[]; meta?: { total?: number } }>("api_admin_list_zones", {
    p_status: null, p_q: null, p_sort: "-updated_at", p_page: 1, p_limit: 100, p_include_archived: true,
  });
  const firstRows = first.data ?? [];
  const total = first.meta?.total ?? firstRows.length;
  if (firstRows.length >= total) return firstRows;
  const pageCount = Math.ceil(total / 100);
  const rest = await Promise.all(Array.from({ length: pageCount - 1 }, (_, i) => call<{ data: ZoneSummary[] }>("api_admin_list_zones", {
    p_status: null, p_q: null, p_sort: "-updated_at", p_page: i + 2, p_limit: 100, p_include_archived: true,
  })));
  return firstRows.concat(...rest.map((page) => page.data ?? []));
}

/** The SQL contract scopes history by zone; the no-id view joins the paged zone and history RPCs. */
export async function zoneHistory(id?: string): Promise<ZoneHistoryItem[]> {
  if (demoMode()) return demo.zoneHistory(id);
  if (id) {
    const zone = await zoneDetail(id);
    return zoneHistoryPages(id, zone.name);
  }
  const summaries = await allZoneSummaries();
  const history = await Promise.all(summaries.map((zone) => zoneHistoryPages(zone.id, zone.name)));
  return history.flat().sort((a, b) => b.changed_at.localeCompare(a.changed_at) || b.id - a.id);
}

export async function editZone(id: string, input: EditZoneInput): Promise<ZoneDetailWithAggregate> {
  if (demoMode()) return demo.editZone(id, input);
  const data = await call<ZoneDetailWithAggregate>("api_admin_edit_zone", { p_id: id, p: input });
  invalidateHeatmapSnapshot();
  changed();
  return data;
}

export async function editZoneStatus(id: string, input: EditStatusInput): Promise<ZoneDetailWithAggregate> {
  if (demoMode()) return demo.editZoneStatus(id, input);
  const data = await call<unknown>("api_admin_edit_zone_status", { p_id: id, p: input });
  invalidateHeatmapSnapshot();
  changed();
  // The `normal` response is a release receipt; reload detail for the stable component shape.
  return input.status === "normal" ? zoneDetail(id) : data as ZoneDetailWithAggregate;
}

