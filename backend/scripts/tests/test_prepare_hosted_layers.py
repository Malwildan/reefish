"""Focused tests for the local-only hosted layer SQL generator."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "prepare_hosted_layers.py"
SPEC = importlib.util.spec_from_file_location("prepare_hosted_layers", SCRIPT)
module = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(module)


class PrepareHostedLayersTests(unittest.TestCase):
    def test_sql_text_escapes_single_quotes(self):
        self.assertEqual(module.sql_text("O'Brien"), "'O''Brien'")

    def test_prepare_writes_chunked_idempotent_sql_and_hash_manifest(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            predictions = root / "predictions"
            assets = root / "assets"
            out = root / "out"
            predictions.mkdir()
            assets.mkdir()

            (predictions / "metadata.json").write_text(json.dumps({
                "label_basis": "relative cluster score",
                "periods": [{"period": "2025-12", "file": "clusters_2025-12.geojson", "count": 1}],
            }), encoding="utf-8")
            feature = {
                "type": "Feature",
                "properties": {
                    "grid_id": "X001_Y001", "period": "2025-12", "cluster_id": 0,
                    "level_cluster": 2, "potential_score": 0.5, "sst": None,
                    "chlor_a": 1.2, "depth_m": 20, "fitur_diimputasi": False,
                },
                "geometry": {"type": "Point", "coordinates": [112.7, -8.4]},
            }
            (predictions / "clusters_2025-12.geojson").write_text(json.dumps({
                "type": "FeatureCollection", "features": [feature],
            }), encoding="utf-8")
            (assets / "potensi_ikan.csv").write_text(
                "grid_x,grid_y,value\n1,1,16.35\n", encoding="utf-8")
            polygon = {"type": "Polygon", "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]}
            for filename, props in (
                ("coral.geojson", {"value": 1}),
                ("mangrove.geojson", {"gridcode": 1, "year": 2023, "area_km2": 2.0, "area_clip_km2": 1.5}),
            ):
                (assets / filename).write_text(json.dumps({
                    "type": "FeatureCollection",
                    "features": [{"type": "Feature", "properties": props, "geometry": polygon}],
                }), encoding="utf-8")

            manifest = module.prepare(predictions, assets, out, batch_size=1, expected_grid_cells=1)

            self.assertEqual(manifest["period"], "2025-12")
            self.assertEqual(manifest["prediction_rows"], 1)
            self.assertEqual(manifest["grid_layer_rows"], 1)
            self.assertEqual(len(manifest["sources"]), 5)
            self.assertTrue(all(len(source["sha256"]) == 64 for source in manifest["sources"]))
            sql = "\n".join(path.read_text(encoding="utf-8") for path in out.glob("*.sql"))
            self.assertIn("ON CONFLICT (grid_id, period) DO UPDATE", sql)
            self.assertIn("ON CONFLICT (grid_id) DO UPDATE", sql)
            self.assertIn("ST_MakeValid", sql)
            self.assertIn("potential_score_interpretation", manifest["provenance"])
            self.assertNotIn("TRUNCATE", sql.upper())


if __name__ == "__main__":
    unittest.main()
