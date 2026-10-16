// node --test src/features/geo/heatmap-parse.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";
import { toApiError } from "../../lib/api/error.ts";
import { autoFlags, decodeSeaMask, parseHeatmap, zoneIndex } from "./heatmap-parse.ts";

test("parses api_heatmap tuples by column name", () => {
  const h = parseHeatmap({
    heatmap_version: 7,
    window: "30d",
    generated_at: "2026-10-16T00:00:00Z",
    scale: { fatigue: { min: 0, max: 1, thresholds: { tired: 0.4, critical: 0.7 } }, pressure: { min: 0, max: 1 }, cpue: { min: 0, max: null, unit: "kg/jam" } },
    columns: ["grid_id", "fatigue", "fatigue_level", "pressure", "cpue", "has_coral", "zone_id", "auto_flag"],
    cells: [
      ["X100_Y152", 0.97, "critical", 0.4, null, true, null, "restricted"],
      ["X098_Y153", 0, "healthy", 0, null, true, "z1", null],
    ],
    zones: { z1: { id: "z1", name: "Rehab", status: "rehab", grid_ids: ["X098_Y153"], zone_version: 1 } },
  });
  assert.equal(h.cells[0].fatigueLevel, "critical");
  assert.equal(h.cells[0].autoFlag, "restricted");
  assert.deepEqual(autoFlags(h), ["X100_Y152"]);
  assert.equal(zoneIndex(h)["X098_Y153"].status, "rehab");
});

test("decodes the sea mask bitset (MSB first, y then x)", () => {
  // 3 columns x 2 rows: cells 0 and 4 are sea -> bits 1000 1000 -> 0x88
  const ids = decodeSeaMask({ bits: btoa(String.fromCharCode(0x88)), cols: 3, length: 6 });
  assert.deepEqual(ids, ["X001_Y001", "X002_Y002"]);
});

test("maps private.fail errors to ApiError", () => {
  const e = toApiError({ message: "GRID_CONFLICT", hint: "Grid bentrok", details: '{"conflicts":[1]}', code: "P0001" });
  assert.equal(e.code, "GRID_CONFLICT");
  assert.equal(e.message, "Grid bentrok");
  assert.deepEqual(e.details, { conflicts: [1] });
  assert.equal(toApiError({ message: "JWT expired", code: "PGRST301" }).code, "PGRST301");
});
