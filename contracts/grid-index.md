# Grid index contract

**Owner:** Backend. Every client (Flutter, Next.js, ML, Go) must reproduce `fixtures/grid-index-vectors.json` before relying on its own grid code. The reference implementation is `backend/api/internal/domain/gridindex`, and its test reads the same fixture.

## Grid

The grid is fixed: 500 × 500 m squares in WGS 84 / UTM zone 49S (EPSG:32749). It is the same grid as the ML data (guide section 7) and as main's grid lock (`grid-locks.md`). Only the identifiers differ.

| Item | Value |
|---|---|
| Lower-left corner of `X001_Y001` | E = 637500, N = 8988000 (m) |
| Index range | `grid_x` 1..187 (east), `grid_y` 1..177 (north); 31,354 cells have data |
| Data ID | `X{grid_x:03}_Y{grid_y:03}`, e.g. `X149_Y001` (`grid_cells.grid_id`) |
| Canonical ID (main) | `tp-id-utm49s-500m:v2:rp{row}:cp{col}` with `row = grid_y + 17975`, `col = grid_x + 1274` (`grid_cells.cell_id`) |
| Pilot bbox | `[112.25, -9.15, 113.10, -8.35]` (lon/lat) |

## Formulas

```
(E, N)  = project lon/lat (EPSG:4326) to EPSG:32749
grid_x  = floor((E - 637500) / 500) + 1
grid_y  = floor((N - 8988000) / 500) + 1
row     = floor(N / 500)          = grid_y + 17975
col     = floor(E / 500)          = grid_x + 1274
centre  = (637500 + (grid_x - 0.5) * 500, 8988000 + (grid_y - 0.5) * 500), then project back to lon/lat
```

**Edges:** the left and bottom edges are inclusive, the right and top edges exclusive. A point exactly on a shared edge belongs to the east/north cell. Decide edges in metres (UTM), never in degrees.

**Range:** an index inside the 187 × 177 range does not guarantee data for that cell (`has_data` in the fixture). A missing cell is "no data", never zero and never land.

**Precision:** the fixture comes from PostGIS `ST_Transform`. An implementation passes when lon/lat differ by at most `1e-7`° and UTM by at most `0.01` m, and every index matches exactly. The reference uses Snyder's Transverse Mercator series (USGS PP 1395); `proj4dart` and `pyproj` also pass.

## Fixture

Each vector in `fixtures/grid-index-vectors.json` has:
- `input`: what the case starts from (`lon`/`lat`, `easting`/`northing`, `grid_id`, or `cell_id`)
- `lon`, `lat`, `easting`, `northing`
- `grid_x`, `grid_y`, `grid_id` (null outside the 999 range)
- `cell_id`, `in_pilot_range`, `has_data`

The cases cover data cell centres, the `grid-locks.md` example (a cell without data), the corner and exact edges, 1 mm west of an edge, the north-east corner, a point outside the bbox, and a point near Sendang Biru.
