"""Prepare idempotent, bounded SQL batches for importing Reefish map layers.

This script only reads local sources and writes SQL plus a provenance manifest to
backend/out/integration. It never connects to Supabase and never truncates tables.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Iterable


REPO = Path(__file__).resolve().parents[2]
DEFAULT_ASSETS = REPO / "frontend" / "mobile" / "assets" / "geodata"
DEFAULT_OUT = REPO / "backend" / "out" / "integration"
DEFAULT_PREDICTIONS = REPO / "machine-learning" / "data" / "geojson"
DEFAULT_BATCH_SIZE = 1000


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def sql_num(value: Any, *, nullable: bool = False) -> str:
    if value is None and nullable:
        return "NULL"
    if isinstance(value, bool):
        raise ValueError("boolean is not a numeric layer value")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"non-finite numeric value: {value!r}")
    return repr(number)


def sql_bool(value: Any) -> str:
    if not isinstance(value, bool):
        raise ValueError(f"expected boolean, got {value!r}")
    return "TRUE" if value else "FALSE"


def read_features(path: Path) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("type") != "FeatureCollection" or not isinstance(data.get("features"), list):
        raise ValueError(f"{path}: expected GeoJSON FeatureCollection")
    return data["features"]


def geom_expr(geometry: dict[str, Any]) -> str:
    if geometry.get("type") not in {"Polygon", "MultiPolygon"}:
        raise ValueError(f"unsupported habitat geometry: {geometry.get('type')!r}")
    encoded = json.dumps(geometry, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    raw = f"extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON({sql_text(encoded)}), 4326)"
    # Source files are already processed, but this keeps invalid edge cases from
    # failing the whole load while preserving polygonal components only.
    return f"extensions.ST_Multi(extensions.ST_CollectionExtract(extensions.ST_MakeValid({raw}), 3))"


def chunks(rows: list[str], size: int) -> Iterable[list[str]]:
    for start in range(0, len(rows), size):
        yield rows[start : start + size]


def write_batches(
    out: Path,
    stem: str,
    table: str,
    columns: tuple[str, ...],
    rows: list[str],
    batch_size: int,
    conflict: str,
) -> list[Path]:
    outputs = []
    for index, batch in enumerate(chunks(rows, batch_size), start=1):
        path = out / f"{stem}_{index:03}.sql"
        path.write_text(
            "BEGIN;\n"
            f"INSERT INTO public.{table} ({', '.join(columns)}) VALUES\n  "
            + ",\n  ".join(batch)
            + f"\nON CONFLICT {conflict};\nCOMMIT;\n",
            encoding="utf-8",
            newline="\n",
        )
        outputs.append(path)
    return outputs


def prepare(
    predictions_dir: Path,
    assets_dir: Path,
    out: Path,
    period: str = "latest",
    batch_size: int = DEFAULT_BATCH_SIZE,
    expected_grid_cells: int = 31354,
) -> dict[str, Any]:
    if batch_size < 1 or batch_size > 1000:
        raise ValueError("batch size must be between 1 and 1000")
    metadata_path = predictions_dir / "metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    periods = {item["period"]: item for item in metadata["periods"]}
    if not periods:
        raise ValueError("prediction metadata has no periods")
    chosen_period = max(periods) if period == "latest" else period
    if chosen_period not in periods:
        raise ValueError(f"period {chosen_period!r} is not in metadata")
    prediction_path = predictions_dir / periods[chosen_period]["file"]
    prediction_features = read_features(prediction_path)
    if len(prediction_features) != periods[chosen_period]["count"]:
        raise ValueError("prediction feature count does not match metadata")

    prediction_rows: list[str] = []
    prediction_grid_ids: set[str] = set()
    for feature in prediction_features:
        prop = feature["properties"]
        geom = feature["geometry"]
        if geom.get("type") != "Point" or len(geom.get("coordinates", [])) != 2:
            raise ValueError("cluster prediction must use a WGS84 GeoJSON Point")
        grid_id = str(prop["grid_id"])
        if grid_id in prediction_grid_ids:
            raise ValueError(f"duplicate prediction grid {grid_id}")
        prediction_grid_ids.add(grid_id)
        if prop.get("period") != chosen_period:
            raise ValueError(f"feature period does not match {chosen_period}")
        prediction_rows.append(
            "(" + ", ".join([
                sql_text(grid_id), sql_text(chosen_period), str(int(prop["cluster_id"])),
                str(int(prop["level_cluster"])), sql_num(prop["potential_score"]),
                sql_num(prop.get("sst"), nullable=True), sql_num(prop.get("chlor_a"), nullable=True),
                sql_num(prop.get("depth_m"), nullable=True),
                sql_bool(prop["fitur_diimputasi"]),
            ]) + ")"
        )
    if len(prediction_grid_ids) != expected_grid_cells:
        raise ValueError(f"expected {expected_grid_cells} grid cells, got {len(prediction_grid_ids)}")

    layer_path = assets_dir / "potensi_ikan.csv"
    layer_rows: list[str] = []
    layer_ids: set[str] = set()
    with layer_path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        if not {"grid_x", "grid_y", "value"}.issubset(reader.fieldnames or []):
            raise ValueError("potensi_ikan.csv needs grid_x, grid_y, and value columns")
        for record in reader:
            grid_id = f"X{int(record['grid_x']):03d}_Y{int(record['grid_y']):03d}"
            if grid_id in layer_ids:
                raise ValueError(f"duplicate potensi_ikan grid {grid_id}")
            if grid_id not in prediction_grid_ids:
                raise ValueError(f"potensi_ikan grid is absent from predictions: {grid_id}")
            layer_ids.add(grid_id)
            layer_rows.append(f"({sql_text(grid_id)}, {sql_num(record['value'])})")
    if layer_ids != prediction_grid_ids:
        raise ValueError(f"grid layer coverage differs from predictions ({len(layer_ids)} vs {len(prediction_grid_ids)})")

    coral_path = assets_dir / "coral.geojson"
    mangrove_path = assets_dir / "mangrove.geojson"
    coral_features = read_features(coral_path)
    mangrove_features = read_features(mangrove_path)
    coral_rows = []
    for index, feature in enumerate(coral_features):
        prop = feature.get("properties", {})
        coral_rows.append(f"({index}, {sql_num(prop['value'])}, {geom_expr(feature['geometry'])})")
    mangrove_rows = []
    for index, feature in enumerate(mangrove_features):
        prop = feature.get("properties", {})
        mangrove_rows.append("(" + ", ".join([
            str(index), sql_num(prop.get("gridcode"), nullable=True),
            sql_num(prop.get("year"), nullable=True), sql_num(prop.get("area_km2"), nullable=True),
            sql_num(prop.get("area_clip_km2"), nullable=True), geom_expr(feature["geometry"]),
        ]) + ")")

    out.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    files += write_batches(out, f"cluster_predictions_{chosen_period}", "cluster_predictions",
        ("grid_id", "period", "cluster_id", "level", "potential_score", "sst", "chlor_a", "depth_m", "imputed"),
        prediction_rows, batch_size,
        "(grid_id, period) DO UPDATE SET cluster_id = EXCLUDED.cluster_id, level = EXCLUDED.level, "
        "potential_score = EXCLUDED.potential_score, sst = EXCLUDED.sst, chlor_a = EXCLUDED.chlor_a, "
        "depth_m = EXCLUDED.depth_m, imputed = EXCLUDED.imputed")
    files += write_batches(out, "grid_layers", "grid_layers", ("grid_id", "potensi_ikan"), layer_rows,
        batch_size, "(grid_id) DO UPDATE SET potensi_ikan = EXCLUDED.potensi_ikan")
    files += write_batches(out, "coral_areas", "coral_areas", ("id", "value", "geom"), coral_rows,
        batch_size, "(id) DO UPDATE SET value = EXCLUDED.value, geom = EXCLUDED.geom")
    # Add explicit casts at insertion for geometry literals, since CSV imports are not used here.
    files += write_batches(out, "mangrove_areas", "mangrove_areas",
        ("id", "gridcode", "year", "area_km2", "area_clip_km2", "geom"), mangrove_rows,
        batch_size, "(id) DO UPDATE SET gridcode = EXCLUDED.gridcode, year = EXCLUDED.year, "
        "area_km2 = EXCLUDED.area_km2, area_clip_km2 = EXCLUDED.area_clip_km2, geom = EXCLUDED.geom")

    sources = [metadata_path, prediction_path, layer_path, coral_path, mangrove_path]
    manifest = {
        "format_version": 1,
        "period": chosen_period,
        "batch_size": batch_size,
        "prediction_rows": len(prediction_rows),
        "grid_layer_rows": len(layer_rows),
        "coral_features": len(coral_rows),
        "mangrove_features": len(mangrove_rows),
        "sql_files": [path.name for path in files],
        "sources": [{"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)} for path in sources],
        "provenance": {
            "rights_status": "not documented in the repository; verify source terms before public redistribution",
            "cluster_label_basis": metadata.get("label_basis"),
            "potential_score_interpretation": "model-relative prediction score; not fish abundance or catch guarantee",
            "potensi_ikan": "separate dataset; units and provenance remain unconfirmed",
            "habitat": "processed mobile GeoJSON assets; source rights and coral codebook remain unconfirmed",
        },
    }
    manifest_path = out / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--predictions", type=Path, default=DEFAULT_PREDICTIONS,
        help="folder containing clusters_YYYY-MM.geojson and metadata.json")
    parser.add_argument("--assets", type=Path, default=DEFAULT_ASSETS,
        help="folder containing potensi_ikan.csv, coral.geojson, and mangrove.geojson")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--period", default="latest", help="period to export, or latest (default)")
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    args = parser.parse_args()
    result = prepare(args.predictions, args.assets, args.out, args.period, args.batch_size)
    print(json.dumps({k: result[k] for k in ("period", "prediction_rows", "grid_layer_rows", "coral_features", "mangrove_features")}, indent=2))
    print(f"SQL batches and manifest written to {args.out}")


if __name__ == "__main__":
    main()
