"""Convert data/geojson cluster files into CSVs for psql \\copy.

Usage: python scripts/geojson_to_csv.py data/geojson out
"""
import csv
import json
import sys
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
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
