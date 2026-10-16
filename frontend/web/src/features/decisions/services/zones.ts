// Admin zone RPCs (contracts/map-zones-api.openapi.yaml). Every call runs as the signed-in
// konservatif; the role check, validation and error codes live in the SQL functions.
import { rpc } from "@/lib/api/rpc";
import { getHeatmap } from "@/features/geo/services/heatmap";
import { autoFlags, zoneIndex } from "@/features/geo/heatmap-parse";
import type {
  CreateZoneInput,
  EditStatusInput,
  EditZoneInput,
  GridDetail,
  RefreshJob,
  StatsSummary,
  Suggestions,
  ZoneAggregate,
  ZoneDetailWithAggregate,
  ZoneHistoryItem,
  ZonePreview,
  ZoneStatus,
  ZoneSummary,
} from "../types";

// Mutations bump this so every useZoneQuery refetches.
let version = 0;
const listeners = new Set<() => void>();
export function subscribe(l: () => void) {
  listeners.add(l);
  return () => void listeners.delete(l);
}
export const getVersion = () => version;
function changed<T>(v: T) {
  version++;
  listeners.forEach((l) => l());
  return v;
}

type RawPreview = {
  valid_grid_ids: string[];
  invalid_grid_ids: string[];
  conflicts: { grid_id: string; zone_id: string; zone_name: string }[];
  aggregate: ZoneAggregate;
};

/**
 * api_admin_preview_zone, plus each conflict's zone status and the system auto-flags (both from
 * api_heatmap). Rehab cells can never join a new zone, so when the selection has some the
 * aggregate is fetched again without them.
 */
export async function previewZone(gridIds: string[]): Promise<ZonePreview> {
  const [raw, heat] = await Promise.all([
    rpc<RawPreview>("api_admin_preview_zone", { p: { grid_ids: gridIds } }),
    getHeatmap("30d"),
  ]);
  const zones = zoneIndex(heat);
  const conflicts = raw.conflicts.map((c) => ({ ...c, zone_status: zones[c.grid_id]?.status ?? ("restricted" as ZoneStatus) }));
  const rehab = new Set(conflicts.filter((c) => c.zone_status === "rehab").map((c) => c.grid_id));
  const inZone = raw.valid_grid_ids.filter((g) => !rehab.has(g));
  let aggregate = raw.aggregate;
  if (rehab.size && inZone.length) {
    aggregate = (await rpc<RawPreview>("api_admin_preview_zone", { p: { grid_ids: inZone } })).aggregate;
  }
  const flags = new Set(autoFlags(heat));
  return { aggregate, conflicts, invalid_grid_ids: raw.invalid_grid_ids, auto_flagged_grid_ids: inZone.filter((g) => flags.has(g)) };
}

export async function createZone(p: CreateZoneInput) {
  return changed(await rpc<ZoneDetailWithAggregate>("api_admin_create_zone", { p }));
}

export async function listZones(opts: { status?: ZoneStatus; includeArchived?: boolean } = {}): Promise<ZoneSummary[]> {
  const res = await rpc<{ data: ZoneSummary[] }>("api_admin_list_zones", {
    p_status: opts.status ?? null,
    p_include_archived: opts.includeArchived ?? false,
    p_limit: 100,
  });
  return res.data;
}

export const zoneDetail = (id: string) => rpc<ZoneDetailWithAggregate>("api_admin_zone_detail", { p_id: id });

/** One zone's history, or (no id) every zone's history merged, newest first. */
export async function zoneHistory(id?: string): Promise<ZoneHistoryItem[]> {
  const one = async (zoneId: string, name: string) => {
    const res = await rpc<{ data: Omit<ZoneHistoryItem, "zone_id" | "zone_name">[] }>("api_admin_zone_history", {
      p_id: zoneId,
      p_limit: 100,
    });
    return res.data.map((h) => ({ ...h, zone_id: zoneId, zone_name: name }));
  };
  if (id) return one(id, (await zoneDetail(id)).name);
  // shortcut: one call per zone (the RPC needs p_id); add a cross-zone history RPC if zones grow to hundreds
  const zones = await listZones({ includeArchived: true });
  const all = (await Promise.all(zones.map((z) => one(z.id, z.name)))).flat();
  return all.sort((a, b) => b.changed_at.localeCompare(a.changed_at) || b.id - a.id);
}

export async function editZone(id: string, p: EditZoneInput) {
  return changed(await rpc<ZoneDetailWithAggregate>("api_admin_edit_zone", { p_id: id, p }));
}

export async function editZoneStatus(id: string, p: EditStatusInput) {
  return changed(await rpc<{ id: string; status: string }>("api_admin_edit_zone_status", { p_id: id, p }));
}

/** api_admin_edit_zone_grids. Rehab cells of other zones are never sent (UI rule). */
export async function editZoneGrids(id: string, p: { add: string[]; remove: string[]; reason: string; version: number }) {
  return changed(
    await rpc<ZoneDetailWithAggregate>("api_admin_edit_zone_grids", { p_id: id, p: { ...p, on_conflict: "move" } }),
  );
}

export const gridDetail = (gridId: string) => rpc<GridDetail>("api_admin_grid_detail", { p_grid_id: gridId });

export const suggestions = () => rpc<Suggestions>("api_admin_suggestions", { p_limit: 50 });

export const statsSummary = (window: "7d" | "30d") => rpc<StatsSummary>("api_admin_stats_summary", { p_window: window });

/** Queues a full refresh; pg_cron runs it within ~10 s. Poll refreshStatus(job_id). */
export const refreshHeatmap = (reason: string) =>
  rpc<RefreshJob>("api_admin_refresh_heatmap", { p: { scope: "all", reason } });

export async function refreshStatus(jobId: string) {
  const job = await rpc<RefreshJob>("api_admin_refresh_status", { p_job_id: jobId });
  // a finished job published a new heatmap: refetch everything on screen
  return job.status === "done" ? changed(job) : job;
}
