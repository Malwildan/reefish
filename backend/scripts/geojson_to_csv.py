"""Convert ML cluster GeoJSON (and optional habitat/layer files) into CSVs for psql \\copy.

Usage:
  python scripts/geojson_to_csv.py ../machine-learning/data/geojson out \\
    --coral ../machine-learning/data/processed/geodata/coral.geojson \\
    --mangrove ../machine-learning/data/processed/geodata/mangrove.geojson \\
    --potensi-ikan ../machine-learning/data/raw/layers/potensi_ikan.csv
"""
import argparse
import csv
import json
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("src", type=Path, help="folder with clusters_*.geojson + metadata.json")
ap.add_argument("out", type=Path)
ap.add_argument("--coral", type=Path)
ap.add_argument("--mangrove", type=Path)
ap.add_argument("--potensi-ikan", type=Path)
args = ap.parse_args()
src, out = args.src, args.out
out.mkdir(parents=True, exist_ok=True)
meta = json.loads((src / "metadata.json").read_text(encoding="utf-8"))

grid = {}
total = 0
with open(out / "cluster_predictions.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["grid_id", "period", "cluster_id", "level", "potential_score", "sst", "chlor_a", "depth_m", "imputed"])
    for p in meta["periods"]:
        features = json.loads((src / p["file"]).read_text(encoding="utf-8"))["features"]
        assert len(features) == p["count"], f"{p['file']}: {len(features)} != {p['count']}"
        for ft in features:
            pr = ft["properties"]
            lon, lat = ft["geometry"]["coordinates"]
            if grid.setdefault(pr["grid_id"], (lon, lat)) != (lon, lat):
                raise ValueError(f"{pr['grid_id']} moved in {p['period']}")
            w.writerow([pr["grid_id"], pr["period"], pr["cluster_id"], pr["level_cluster"], pr["potential_score"],
                        pr["sst"], pr["chlor_a"], pr["depth_m"], "t" if pr["fitur_diimputasi"] else "f"])
        total += len(features)
        print(p["period"], len(features))

assert total == meta["total_exported_points"], f"{total} != {meta['total_exported_points']}"

with open(out / "grid_cells.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["grid_id", "geom"])
    for gid, (lon, lat) in grid.items():
        w.writerow([gid, f"SRID=4326;POINT({lon} {lat})"])

print(f"{len(grid)} grid cells, {total} predictions")


def multipolygon_wkt(geom):
    """GeoJSON Polygon/MultiPolygon -> EWKT MULTIPOLYGON; holes are kept."""
    if geom["type"] not in ("Polygon", "MultiPolygon"):
        raise ValueError(f"unsupported geometry {geom['type']}")
    polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
    ring = lambda r: "(" + ",".join(f"{p[0]} {p[1]}" for p in r) + ")"
    return "SRID=4326;MULTIPOLYGON(" + ",".join("(" + ",".join(ring(r) for r in poly) + ")" for poly in polys) + ")"


def features(path):
    return json.loads(path.read_text(encoding="utf-8"))["features"]


if args.coral:
    coral = features(args.coral)
    with open(out / "coral_areas.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "value", "geom"])
        for i, ft in enumerate(coral):
            w.writerow([i, ft["properties"]["value"], multipolygon_wkt(ft["geometry"])])
    print(f"{len(coral)} coral areas")

if args.mangrove:
    mangrove = features(args.mangrove)
    with open(out / "mangrove_areas.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "gridcode", "year", "area_km2", "area_clip_km2", "geom"])
        for i, ft in enumerate(mangrove):
            pr = ft["properties"]
            w.writerow([i, pr["gridcode"], pr["year"], pr["area_km2"], pr["area_clip_km2"], multipolygon_wkt(ft["geometry"])])
    print(f"{len(mangrove)} mangrove areas")

if args.potensi_ikan:
    rows = 0
    with open(args.potensi_ikan, newline="", encoding="utf-8") as fin, \
            open(out / "grid_layers.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["grid_id", "potensi_ikan"])
        for r in csv.DictReader(fin):
            gid = f"X{int(r['grid_x']):03d}_Y{int(r['grid_y']):03d}"
            if gid not in grid:
                raise ValueError(f"potensi_ikan {gid} is not a grid cell")
            w.writerow([gid, float(r["value"])])
            rows += 1
    print(f"{rows} potensi_ikan cells")
