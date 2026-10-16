# Hosted Supabase setup and endpoint queries

The project is `upyahsecuorqghcghflg`. The source of truth for the schema is `../migrations/*.sql`. `hosted_setup.sql` is generated from those migrations; do not edit it.

Regenerate it from `backend/supabase`:

```sh
{ printf -- '-- GENERATED: do not edit. Source of truth is supabase/migrations/*.sql.\n-- Regenerate from backend/supabase: see setup/README.md.\n-- Run once in the Supabase SQL Editor on an empty project; everything commits or nothing does.\nbegin;\n'; for f in migrations/*.sql; do printf '\n-- ===== %s =====\n' "$f"; cat "$f"; done; printf '\ncommit;\n'; } > setup/hosted_setup.sql
```

## 1. Create the schema (choose one)

**A. CLI (recommended).** Migration history is recorded, so a later `db push` runs only new migrations.

```sh
npx supabase login
npx supabase link --project-ref upyahsecuorqghcghflg
npx supabase db push
```

**B. SQL Editor.**
1. Open Table Editor first and make sure `profiles` and `zones` do not exist yet. The script fails on a project that already has them.
2. Open SQL Editor and create a new query.
3. Paste the whole `hosted_setup.sql` and run it. The script runs as one transaction, so either everything is created or nothing is.

This option does not record migration history. Before you use the CLI later, run this once:

```sh
npx supabase migration repair --status applied 0001 0002 0003 0004 0005 0006
```

## 2. Auth settings (SQL cannot set these)

Without these settings, register can bypass the password rules in the Edge Function.

Set them in the dashboard under Authentication → Sign In / Providers:
- Turn off "Allow new users to sign up".
- Under Email: set "Minimum password length" to 8.

Alternatively, run `npx supabase config push`. This overwrites every hosted auth setting with `config.toml`.

Deploy the auth Edge Functions:

```sh
npx supabase functions deploy auth-register auth-login
```

## 3. Data import

Map, recommendation and in-pilot checks need `grid_cells` and `cluster_predictions`.
1. Generate the CSVs:

   ```sh
   M=../machine-learning/data
   python scripts/geojson_to_csv.py $M/geojson out --coral $M/processed/geodata/coral.geojson \
     --mangrove $M/processed/geodata/mangrove.geojson --potensi-ikan $M/raw/layers/potensi_ikan.csv
   ```

2. Import them in Table Editor (`grid_cells`, then `cluster_predictions`), or run:

```sh
psql "$SUPABASE_DB_URL" -c "\copy grid_cells(grid_id, geom) from 'out/grid_cells.csv' csv header"
psql "$SUPABASE_DB_URL" -c "\copy cluster_predictions from 'out/cluster_predictions.csv' csv header"
psql "$SUPABASE_DB_URL" -c "\copy coral_areas(id, value, geom) from 'out/coral_areas.csv' csv header"
psql "$SUPABASE_DB_URL" -c "\copy mangrove_areas(id, gridcode, year, area_km2, area_clip_km2, geom) from 'out/mangrove_areas.csv' csv header"
psql "$SUPABASE_DB_URL" -c "\copy grid_layers(grid_id, potensi_ikan) from 'out/grid_layers.csv' csv header"
psql "$SUPABASE_DB_URL" -c "select private.refresh_coral(); select private.daily_refresh();"
```

The last command marks coral cells and publishes the first full heatmap. pg_cron then runs `private.daily_refresh()` every day at 00:10 WIB (job `heatmap-daily`). Check it in Database → Cron.

## 4. Check

Paste `../tests/nelayan.sql`, `../tests/zones_heatmap.sql`, and `../tests/layers.sql` into the SQL Editor. It creates a test user, runs the whole RPC flow, and rolls everything back. A successful run ends with the notice `nelayan smoke test passed`.

## 5. Queries per endpoint

Every RPC needs the `nelayan` role (`FORBIDDEN` otherwise). An error arrives as `PostgrestException`:
- `message` = the code, for example `BOAT_LIMIT_REACHED`
- `hint` = the message in Indonesian
- `details` = a JSON string

Full schemas are in `contracts/nelayan-api.openapi.yaml`.

To try them in the SQL Editor as a specific user, wrap each query like this. Replace `<uuid>` with an id from Authentication → Users.

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);
-- query here
rollback;  -- use commit; to keep writes
```

### Profile and boat

| Endpoint | Flutter | SQL Editor |
|---|---|---|
| me | `supabase.rpc('api_me')` | `select api_me();` |
| createBoat | `supabase.rpc('api_create_boat', params: {'p': {'name': 'KM Sumber Rejeki', 'engine_hp': 15, 'boat_length_m': 7, 'fuel_type': 'solar', 'home_port': {'lat': -8.43, 'lng': 112.68}}})` | `select api_create_boat('{"name":"KM Sumber Rejeki","engine_hp":15,"boat_length_m":7,"home_port":{"lat":-8.43,"lng":112.68}}');` |
| updateBoat | `supabase.rpc('api_update_boat', params: {'p_id': boatId, 'p': {'engine_hp': 20}})` | `select api_update_boat('<boat uuid>', '{"engine_hp":20}');` |

### Trip

| Endpoint | Flutter | SQL Editor |
|---|---|---|
| postTrip | `supabase.rpc('api_post_trip', params: {'p': trip})` | see below |
| getHistoryTrip | `supabase.rpc('api_list_trips', params: {'p_page': 1, 'p_limit': 20, 'p_sort': '-departed_at'})` | `select api_list_trips(1, 20, null, null, null, '-departed_at');` |
| getTripDetail | `supabase.rpc('api_trip_detail', params: {'p_id': tripId, 'p_track': 'simplified'})` | `select api_trip_detail('<trip uuid>', 'simplified');` |

```sql
select api_post_trip('{
  "client_trip_id": "c0ffee00-0000-4000-8000-000000000001",
  "source": "onboarding",
  "departed_at": "2026-10-15T21:00:00Z",
  "returned_at": "2026-10-16T05:00:00Z",
  "fuel_liters": 25.5,
  "catch_kg": 40,
  "fishing_points": [{"lat": -8.50, "lng": 112.70, "flag_source": "manual"}]
}');
```

Sending the same `client_trip_id` again returns `replay: true` and writes nothing. Run it a second time to check this.

### Config, map and zones

| Endpoint | Flutter | SQL Editor |
|---|---|---|
| getMobileConfig (no login needed) | `supabase.rpc('api_mobile_config')` | `select api_mobile_config();` |
| Fishing spot map | `supabase.rpc('get_fishing_spots', params: {'p_period': '2025-12', 'p_min_level': 4})` | `select get_fishing_spots('2025-12', 4);` |
| Cluster map (konservatif) | `supabase.rpc('get_clusters', params: {'p_period': '2025-12'})` | `select get_clusters('2025-12', 1);` |
| Grid meta / sea mask | `supabase.rpc('api_grid_meta')`, `supabase.rpc('api_sea_mask')` | `select api_grid_meta();` |
| Zones (ZoneEntry) | `supabase.rpc('api_zones', params: {'p_include_outline': true})` | `select api_zones(null, true);` |
| Heatmap | `supabase.rpc('api_heatmap', params: {'p_window': '30d'})` | `select api_heatmap('30d');` |
| ML layers per period | `supabase.rpc('api_layers', params: {'p_period': '2025-12'})` | `select api_layers('2025-12');` |
| Coral + mangrove | `supabase.rpc('api_habitat')` | `select api_habitat();` |
| Heatmap version / changes | `supabase.rpc('api_heatmap_version')`, `supabase.rpc('api_heatmap_changes', params: {'p_since': v})` | `select api_heatmap_changes(12);` |
| After a sync (instead of X-Heatmap-Version) | `supabase.rpc('api_sync_seen', params: {'p_heatmap_version': v})` | `select api_sync_seen(12);` |
| Push device | `supabase.rpc('api_register_device', params: {'p': {'fcm_token': token}})` | `select api_register_device('{"fcm_token":"abc1234567"}');` |

### Admin konservatif (AGENTS.md 12.A)

| Endpoint | SQL Editor |
|---|---|
| previewZona | `select api_admin_preview_zone('{"grid_ids":["X150_Y040","X151_Y040"]}');` |
| createZona | `select api_admin_create_zone('{"name":"Karang Uji","status":"restricted","grid_ids":["X150_Y040"],"rules":{"max_catch_kg_per_period":500,"period":"weekly"},"reason":"Fatigue tinggi"}');` |
| createZona from a drawn polygon (cells whose centre is inside) | `select api_admin_create_zone('{"name":"Karang Gambar","status":"rehab","polygon":{"type":"Polygon","coordinates":[[[112.60,-8.50],[112.62,-8.50],[112.62,-8.48],[112.60,-8.48],[112.60,-8.50]]]},"reason":"Rehabilitasi"}');` |
| readListZona / readDetailZona | `select api_admin_list_zones();`, `select api_admin_zone_detail('<zone uuid>');` |
| editZona | `select api_admin_edit_zone('<zone uuid>', '{"name":"Karang Uji B","reason":"Ganti nama","version":1}');` |
| editGridZona | `select api_admin_edit_zone_grids('<zone uuid>', '{"add":["X151_Y040"],"reason":"Perluasan","version":2}');` |
| editStatusZona | `select api_admin_edit_zone_status('<zone uuid>', '{"status":"normal","reason":"Pulih","version":3}');` |
| zoneHistory | `select api_admin_zone_history('<zone uuid>');` |
| getGridDetail | `select api_admin_grid_detail('X150_Y040');` |
| listFlags / dismissFlag | `select api_admin_list_flags();`, `select api_admin_dismiss_flags('{"grid_ids":["X150_Y040"],"reason":"Musiman"}');` |
| refreshHeatmap / getRefreshStatus | `select api_admin_refresh_heatmap('{"scope":"all","reason":"Update data"}');`, `select api_admin_refresh_status('<job uuid>');` |
| statsSummary | `select api_admin_stats_summary('30d');` |
| automaticFlagToRestricted (service_role / postgres only) | `select api_internal_auto_flag(null, true);` |

From Next.js the call is the same, for example `supabase.rpc('api_admin_create_zone', { p: {...} })`.

### Auth (Edge Functions)

```sh
curl -X POST https://upyahsecuorqghcghflg.supabase.co/functions/v1/auth-register \
  -H "Content-Type: application/json" -d '{"phone":"081234567890","password":"Rahasia#123","full_name":"Budi"}'
curl -X POST https://upyahsecuorqghcghflg.supabase.co/functions/v1/auth-login \
  -H "Content-Type: application/json" -d '{"phone":"081234567890","password":"Rahasia#123"}'
```

Pass `session.access_token` from the response to Flutter with `supabase.auth.setSession(refresh_token)`, or send it as `Authorization: Bearer` to the Go service.

### Promote a konservatif account (SQL Editor, as postgres)

```sql
update profiles set role = 'konservatif' where phone = '6281234567890';
```

### Go service (computation, not Supabase)

`GET /api/v1/recommendations` and `GET /api/v1/weather` with `Authorization: Bearer <access_token>`. Behind the scenes these call `api_rec_context`, `api_save_recommendations` and `api_in_pilot`.
