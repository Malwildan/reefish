// node --test src/features/geo/services/heatmap.test.ts (Node >= 23 strips the types)
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseHeatmapSnapshot } from "./heatmap.ts";

const contractSnapshot = {
  heatmap_version: 12,
  generated_at: "2026-10-16T01:02:00Z",
  window: "30d",
  smooth: false,
  scale: { fatigue: { min: 0, max: 1 }, pressure: { min: 0, max: 1 }, cpue: { min: 0, unit: "kg/jam", max: 5.71 } },
  columns: ["grid_id", "fatigue", "fatigue_level", "pressure", "cpue", "has_coral", "zone_id", "auto_flag"],
  cells: [["X149_Y001", 0.12, "healthy", 0.3, 5.71, false, null, null]],
  zones: {},
};

test("maps the documented api_heatmap tuple and preserves unsupported stats as unknown", () => {
  const snapshot = parseHeatmapSnapshot(contractSnapshot);
  assert.equal(snapshot.heatmap_version, 12);
  assert.equal(snapshot.generated_at, "2026-10-16T01:02:00Z");
  assert.deepEqual(snapshot.cells[0], {
    id: "X149_Y001",
    fatigue: 0.12,
    fatigueLevel: "healthy",
    pressure: 0.3,
    cpue: 5.71,
    hasCoral: false,
    zoneId: null,
    autoFlag: null,
    fishers: null,
    trips: null,
    hours: null,
    catchKg: null,
    trend: null,
  });
});

test("rejects malformed tuple shape instead of silently dropping heatmap data", () => {
  assert.throws(() => parseHeatmapSnapshot({ ...contractSnapshot, cells: [["X149_Y001", 0.12]] }), /8-value tuple/);
});
