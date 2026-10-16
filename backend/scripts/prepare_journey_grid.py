#!/usr/bin/env python3
"""Prepare validated journey grid_cells.csv from user-provided point GeoJSON.

This exports only grid_id and the source Point geometry; it does not export or
interpret prediction properties.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path, help="directory with metadata.json and clusters_*.geojson")
    parser.add_argument("output_csv", type=Path)
    parser.add_argument("output_manifest", type=Path)
    args = parser.parse_args()

    source = args.input_dir.resolve()
    metadata_path = source / "metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("geometry_type") != "Point" or metadata.get("coordinate_reference_system") != "WGS84":
        raise ValueError("metadata must declare Point geometry in WGS84")
    if metadata.get("coordinate_order") != ["longitude", "latitude"]:
        raise ValueError("metadata coordinate order must be longitude, latitude")
    periods = metadata.get("periods")
    if not isinstance(periods, list) or len(periods) != 24:
        raise ValueError(f"expected 24 periods, found {len(periods) if isinstance(periods, list) else 'invalid'}")

    canonical: dict[str, tuple[float, float]] = {}
    period_counts: list[dict[str, object]] = []
    total_features = 0
    source_files = [metadata_path]
    for period in periods:
        file_path = source / period["file"]
        source_files.append(file_path)
        document = json.loads(file_path.read_text(encoding="utf-8"))
        features = document.get("features")
        if not isinstance(features, list):
            raise ValueError(f"{file_path.name}: missing features array")
        expected_count = period.get("count")
        if len(features) != expected_count:
            raise ValueError(f"{period['period']}: {len(features)} features != metadata count {expected_count}")
        observed: dict[str, tuple[float, float]] = {}
        for feature in features:
            if feature.get("type") != "Feature" or feature.get("geometry", {}).get("type") != "Point":
                raise ValueError(f"{period['period']}: non-Point feature")
            properties = feature.get("properties") or {}
            grid_id = properties.get("grid_id")
            coords = feature["geometry"].get("coordinates")
            if not isinstance(grid_id, str) or not grid_id or not isinstance(coords, list) or len(coords) != 2:
                raise ValueError(f"{period['period']}: missing grid_id or invalid coordinate pair")
            lon, lat = map(float, coords)
            if not (math.isfinite(lon) and math.isfinite(lat) and -180 <= lon <= 180 and -90 <= lat <= 90):
                raise ValueError(f"{period['period']}: out-of-range/non-finite WGS84 coordinate for {grid_id}: {coords}")
            point = (lon, lat)
            if grid_id in observed:
                raise ValueError(f"{period['period']}: duplicate grid_id {grid_id}")
            observed[grid_id] = point
            if grid_id in canonical and canonical[grid_id] != point:
                raise ValueError(f"{period['period']}: coordinates changed for {grid_id}: {canonical[grid_id]} -> {point}")
            canonical.setdefault(grid_id, point)
        if len(observed) != expected_count:
            raise ValueError(f"{period['period']}: unique grid IDs {len(observed)} != {expected_count}")
        if period_counts and observed.keys() != canonical.keys():
            raise ValueError(f"{period['period']}: grid ID set differs from earlier periods")
        total_features += len(features)
        period_counts.append({"period": period["period"], "feature_count": len(features), "unique_grid_ids": len(observed)})

    if total_features != metadata.get("total_exported_points"):
        raise ValueError(f"total feature count {total_features} != metadata total {metadata.get('total_exported_points')}")
    if len(canonical) != 31354:
        raise ValueError(f"expected exactly 31354 unique source grid IDs, found {len(canonical)}")

    args.output_csv.parent.mkdir(parents=True, exist_ok=True)
    args.output_manifest.parent.mkdir(parents=True, exist_ok=True)
    with args.output_csv.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\n", quoting=csv.QUOTE_MINIMAL)
        writer.writerow(["grid_id", "geom"])
        for grid_id, (lon, lat) in canonical.items():
            writer.writerow([grid_id, f"SRID=4326;POINT({lon!r} {lat!r})"])

    lons = [point[0] for point in canonical.values()]
    lats = [point[1] for point in canonical.values()]
    manifest = {
        "artifact": "journey grid_cells upload CSV",
        "source_directory": str(source),
        "source_metadata": {"file": metadata_path.name, "sha256": sha256(metadata_path)},
        "source_geojson_files": [
            {"file": path.name, "sha256": sha256(path)} for path in source_files[1:]
        ],
        "source_period_count": len(periods),
        "periods": period_counts,
        "total_period_features": total_features,
        "unique_grid_ids": len(canonical),
        "coordinate_validation": {
            "crs": "WGS84 / EPSG:4326",
            "order": "longitude latitude",
            "bounds": {"longitude": [-180, 180], "latitude": [-90, 90]},
            "all_periods_same_grid_ids_and_coordinates": True,
            "source_bbox": [min(lons), min(lats), max(lons), max(lats)],
        },
        "export": {
            "csv": str(args.output_csv.resolve()),
            "columns": ["grid_id", "geom"],
            "geometry_format": "SRID=4326;POINT(longitude latitude)",
            "rows_including_header": len(canonical) + 1,
            "file_size_bytes": args.output_csv.stat().st_size,
            "sha256": sha256(args.output_csv),
            "contains_prediction_fields": False,
            "inferred_footprints_or_resolution": False,
        },
    }
    args.output_manifest.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"grid_ids": len(canonical), "periods": len(periods), "features": total_features,
                      "csv_bytes": args.output_csv.stat().st_size, "csv_sha256": sha256(args.output_csv),
                      "bbox": manifest["coordinate_validation"]["source_bbox"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
