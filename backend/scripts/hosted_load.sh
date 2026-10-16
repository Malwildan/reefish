#!/usr/bin/env bash
# Loads the grid data into hosted Supabase, publishes the first heatmap, runs the smoke tests
# (each rolls back) and, with --demo, adds the demo data. Run from backend/ after `npx supabase db push`:
#   bash scripts/hosted_load.sh [--demo]
# Needs backend/.env.local with SUPABASE_DB_URL=... (Session pooler URL, gitignored) and the CSVs in out/
# (scripts/geojson_to_csv.py). Stops at the first error.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f .env.local ]; then set -a; . ./.env.local; set +a; fi
: "${SUPABASE_DB_URL:?set SUPABASE_DB_URL in backend/.env.local}"
q() { psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -q "$@"; }

if [ "$(q -tAc 'select count(*) from grid_cells')" = "0" ]; then
  q -c "\copy grid_cells(grid_id, geom) from 'out/grid_cells.csv' csv header"
  q -c "\copy cluster_predictions from 'out/cluster_predictions.csv' csv header"
  q -c "\copy coral_areas(id, value, geom) from 'out/coral_areas.csv' csv header"
  q -c "\copy mangrove_areas(id, gridcode, year, area_km2, area_clip_km2, geom) from 'out/mangrove_areas.csv' csv header"
  q -c "\copy grid_layers(grid_id, potensi_ikan) from 'out/grid_layers.csv' csv header"
  q -c "select private.refresh_coral()" -c "select private.daily_refresh()"
else
  echo "grid_cells already loaded, skipping import"
fi
q -tAc "select 'cron: ' || jobname || ' ' || schedule from cron.job"

for t in fixed_grid nelayan zones_heatmap layers; do
  q -f "supabase/tests/$t.sql" > /dev/null 2>"/tmp/reefish_$t.log" || { cat "/tmp/reefish_$t.log"; exit 1; }
  echo "$t ok"
done

if [ "${1:-}" = "--demo" ]; then
  q -c "set reefish.allow_demo = 'on'" -f supabase/seed/demo.sql
  echo "demo data loaded"
fi
