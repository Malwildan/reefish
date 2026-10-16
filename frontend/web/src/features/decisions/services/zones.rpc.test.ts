import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { ApiError, type ZoneDetailWithAggregate } from "../types.ts";
import { setZoneRpcForTests, createZone, editZone, editZoneStatus, listZones, previewZone, zoneDetail, zoneGridIndex, zoneHistory } from "./zones.ts";

const aggregate = {
  grid_count: 1,
  area_km2: 0.25,
  coral_grid_count: 0,
  coral_pct: 0,
  fatigue_avg: 0.2,
  fatigue_max: 0.2,
  fatigue_distribution: { healthy: 1, tired: 0, critical: 0 },
  flagged_grid_count: 0,
  trip_count_30d: 1,
  catch_kg_30d: 5,
  fishing_hours_30d: 2,
  cpue_30d: 2.5,
  violation_count_30d: 0,
  quota: null,
};

const detail: ZoneDetailWithAggregate = {
  id: "11111111-1111-4111-8111-111111111111",
  name: "Zona RPC",
  status: "rehab",
  rules: null,
  reason: "Alasan valid",
  note: null,
  effective_from: "2026-10-16T00:00:00Z",
  effective_until: null,
  grid_ids: ["X100_Y140"],
  is_active: true,
  archived_at: null,
  version: 4,
  created_at: "2026-10-16T00:00:00Z",
  updated_at: "2026-10-16T00:00:00Z",
  aggregate,
};

afterEach(() => setZoneRpcForTests(null));

test("RPC adapter sends contract names and payloads and preserves live responses", async () => {
  const calls: Array<[string, Record<string, unknown>]> = [];
  setZoneRpcForTests(async (name, args = {}) => {
    calls.push([name, args]);
    if (name === "api_admin_preview_zone") return { data: { valid_grid_ids: ["X100_Y140"], invalid_grid_ids: [], conflicts: [], aggregate }, error: null };
    if (name === "api_zones") return { data: { heatmap_version: 3, zones: [{ ...detail, grid_ids: ["X100_Y140"] }] }, error: null };
    if (name === "api_admin_create_zone" || name === "api_admin_zone_detail" || name === "api_admin_edit_zone") return { data: detail, error: null };
    if (name === "api_admin_list_zones") return { data: { data: [{ id: detail.id, name: detail.name, status: detail.status, grid_count: 1, area_km2: .25, fatigue_avg: .2, fatigue_max: .2, quota_remaining_kg: null, quota_exhausted: false, effective_until: null, bbox: null, is_active: true, updated_at: detail.updated_at }], meta: { page: 1, limit: 100, total: 1 } }, error: null };
    if (name === "api_admin_edit_zone_status") return { data: { status: "normal", version: 5 }, error: null };
    if (name === "api_admin_zone_history") return { data: { data: [], meta: { page: 1, limit: 100, total: 0 } }, error: null };
    return { data: null, error: { message: "PGRST202", hint: "missing RPC" } };
  });

  const preview = await previewZone(["X100_Y140"]);
  assert.equal(preview.aggregate.grid_count, 1);
  assert.deepEqual(calls[0], ["api_admin_preview_zone", { p: { grid_ids: ["X100_Y140"] } }]);
  assert.deepEqual(await zoneGridIndex(), { X100_Y140: { id: detail.id, name: detail.name, status: detail.status } });

  await createZone({ name: "Zona RPC", status: "rehab", grid_ids: ["X100_Y140"], rules: null, effective_from: null, effective_until: null, reason: "Alasan valid", note: null });
  await listZones({ status: "rehab", includeArchived: true });
  await zoneDetail(detail.id);
  await editZone(detail.id, { name: "Zona RPC edit", reason: "Alasan edit", version: 4 });
  await editZoneStatus(detail.id, { status: "normal", reason: "Sudah pulih", version: 4 });
  await zoneHistory(detail.id);

  assert.deepEqual(calls.find(([name]) => name === "api_admin_create_zone")?.[1], {
    p: { name: "Zona RPC", status: "rehab", grid_ids: ["X100_Y140"], rules: null, effective_from: null, effective_until: null, reason: "Alasan valid", note: null },
  });
  assert.deepEqual(calls.find(([name]) => name === "api_admin_list_zones")?.[1], {
    p_status: "rehab", p_q: null, p_sort: "-updated_at", p_page: 1, p_limit: 100, p_include_archived: true,
  });
  assert.deepEqual(calls.find(([name]) => name === "api_admin_zone_detail")?.[1], { p_id: detail.id });
  assert.deepEqual(calls.find(([name]) => name === "api_admin_edit_zone")?.[1], { p_id: detail.id, p: { name: "Zona RPC edit", reason: "Alasan edit", version: 4 } });
  assert.deepEqual(calls.find(([name]) => name === "api_admin_edit_zone_status")?.[1], { p_id: detail.id, p: { status: "normal", reason: "Sudah pulih", version: 4 } });
  assert.deepEqual(calls.find(([name]) => name === "api_admin_zone_history")?.[1], { p_id: detail.id, p_action: null, p_page: 1, p_limit: 100 });
});

test("PostgREST conflict errors retain code, message, and structured details", async () => {
  setZoneRpcForTests(async () => ({
    data: null,
    error: { code: "P0001", message: "VERSION_CONFLICT", hint: "Zona telah berubah.", details: '{"current_version":5}' },
  }));
  await assert.rejects(editZone(detail.id, { reason: "Alasan edit", version: 4 }), (error: unknown) => {
    assert.ok(error instanceof ApiError);
    assert.equal(error.code, "VERSION_CONFLICT");
    assert.equal(error.message, "Zona telah berubah.");
    assert.deepEqual(error.details, { current_version: 5 });
    return true;
  });
});
