// node --test src/features/geo/grid.test.ts  (Node >= 23 strips the types)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { cellFromLatLon, cellId, parseCellId, toLatLon, toUTM } from "./grid.ts";

type Vector = { lat: number; lon: number; grid_id: string; easting: number; northing: number };
const fixture = JSON.parse(
  readFileSync(new URL("../../../../../contracts/fixtures/grid-index-vectors.json", import.meta.url), "utf8"),
) as { vectors: Vector[] };

test("matches the shared grid vectors", () => {
  for (const v of fixture.vectors) {
    const [e, n] = toUTM(v.lat, v.lon);
    assert.ok(Math.abs(e - v.easting) < 0.01 && Math.abs(n - v.northing) < 0.01, `${v.grid_id}: ${e} ${n}`);
    const [lat, lon] = toLatLon(e, n);
    assert.ok(Math.abs(lat - v.lat) < 1e-7 && Math.abs(lon - v.lon) < 1e-7, v.grid_id);
    const c = cellFromLatLon(v.lat, v.lon);
    if (/^X\d{3}_Y\d{3}$/.test(v.grid_id)) assert.equal(cellId(c), v.grid_id);
  }
});

test("parses only X{xxx}_Y{yyy}", () => {
  assert.deepEqual(parseCellId("X101_Y153"), { x: 101, y: 153 });
  assert.equal(parseCellId("X1_Y2"), null);
});
