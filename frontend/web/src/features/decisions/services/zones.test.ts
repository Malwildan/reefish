// node --test src/features/decisions/services/zones.test.ts
import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";
import { ApiError } from "../types.ts";
import {
  config,
  createZone,
  editZone,
  editZoneStatus,
  listZones,
  previewZone,
  resetDemo,
  zoneDetail,
  zoneGridIndex,
  zoneHistory,
} from "./zones.ts";

config.latencyMs = 0;
beforeEach(() => resetDemo());

const base = {
  name: "Zona Uji",
  grid_ids: ["X100_Y140", "X101_Y140"],
  effective_from: null,
  effective_until: null,
  reason: "uji coba",
  note: null,
};

async function code(p: Promise<unknown>) {
  try {
    await p;
  } catch (e) {
    assert.ok(e instanceof ApiError);
    return e.code;
  }
  assert.fail("expected an error");
}

test("preview sums the selected cells and reports zone conflicts", async () => {
  const p = await previewZone(["X100_Y140", "X101_Y140", "X100_Y148", "X999_Y999"]);
  assert.equal(p.aggregate.grid_count, 3);
  assert.equal(p.aggregate.area_km2, 0.75);
  assert.deepEqual(p.invalid_grid_ids, ["X999_Y999"]);
  assert.deepEqual(p.conflicts.map((c) => [c.grid_id, c.zone_status]), [["X100_Y148", "rehab"]]);
  assert.ok(p.aggregate.trip_count_30d > 0 && p.aggregate.catch_kg_30d > 0);
});

test("restricted needs rules; conflicts and taken names are rejected", async () => {
  assert.equal(await code(createZone({ ...base, status: "restricted", rules: null })), "RULES_REQUIRED");
  assert.equal(await code(createZone({ ...base, status: "rehab", rules: null, grid_ids: ["X099_Y148"] })), "GRID_CONFLICT");
  assert.equal(await code(createZone({ ...base, status: "rehab", rules: null, name: "karang selatan sempu" })), "ZONE_NAME_TAKEN");
  assert.equal(await code(createZone({ ...base, status: "rehab", rules: null, reason: "" })), "VALIDATION_ERROR");
});

test("create restricted computes quota; rehab drops rules", async () => {
  const z = await createZone({
    ...base,
    status: "restricted",
    rules: { max_catch_kg_per_period: 100000, max_trips_per_period: null, period: "monthly", open_schedule: null },
  });
  assert.equal(z.aggregate.quota?.exhausted, false);
  assert.ok(z.aggregate.quota!.used_kg! > 0);
  const r = await createZone({ ...base, name: "Zona Rehab", grid_ids: ["X090_Y140"], status: "rehab", rules: null });
  assert.equal(r.rules, null);
  assert.equal((await zoneGridIndex())["X090_Y140"].status, "rehab");
});

test("returning to normal archives the zone, releases cells and writes history", async () => {
  const z = await zoneDetail("zona-karang-sempu");
  assert.equal(await code(editZoneStatus(z.id, { status: "normal", reason: "pulih", version: z.version + 1 })), "VERSION_CONFLICT");
  assert.equal(await code(editZoneStatus(z.id, { status: "rehab", reason: "sama", version: z.version })), "SAME_STATUS");
  const done = await editZoneStatus(z.id, { status: "normal", reason: "karang pulih", version: z.version });
  assert.equal(done.is_active, false);
  assert.equal((await zoneGridIndex())["X100_Y148"], undefined);
  assert.equal(await code(editZone(z.id, { reason: "x", version: done.version })), "ZONE_ARCHIVED");
  const h = await zoneHistory(z.id);
  assert.deepEqual(h.slice(0, 2).map((i) => i.action), ["archive", "update_status"]);
  assert.equal(h[1].after?.status, "normal");
  assert.ok(!(await listZones()).some((s) => s.id === z.id));
  assert.ok((await listZones({ includeArchived: true })).some((s) => s.id === z.id));
});

test("rehab to restricted requires rules", async () => {
  const z = await zoneDetail("zona-karang-sempu");
  assert.equal(await code(editZoneStatus(z.id, { status: "restricted", reason: "longgar", version: z.version })), "RULES_REQUIRED");
  const r = await editZoneStatus(z.id, {
    status: "restricted",
    reason: "longgar",
    version: z.version,
    rules: { max_catch_kg_per_period: null, max_trips_per_period: 10, period: "weekly", open_schedule: null },
  });
  assert.equal(r.status, "restricted");
  assert.equal(r.aggregate.quota?.remaining_trips != null, true);
});
