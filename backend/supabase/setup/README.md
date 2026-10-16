# Hosted Supabase setup and endpoint queries

The project is `upyahsecuorqghcghflg`. The source of truth for the schema is `../migrations/*.sql`. `hosted_setup.sql` is generated from the gipar migrations (`20261016100000`…) only; do not edit it.

**The hosted project already has main's grid-lock migrations** (`20261016000020`, `…000217`, `…001628`, applied through MCP). Never re-run them. Push only the gipar migrations.

Regenerate it from `backend/supabase`:

```sh
{ printf -- '-- GENERATED: do not edit. Source of truth is supabase/migrations/*.sql.\n-- Regenerate from backend/supabase: see setup/README.md.\n-- Run once in the Supabase SQL Editor on an empty project; everything commits or nothing does.\nbegin;\n'; for f in migrations/202610161*.sql; do printf '\n-- ===== %s =====\n' "$f"; cat "$f"; done; printf '\ncommit;\n'; } > setup/hosted_setup.sql
```

## 1. Create the schema (choose one)

**A. CLI (recommended).** Migration history is recorded, so a later `db push` runs only new migrations.

```sh
npx supabase login
npx supabase link --project-ref upyahsecuorqghcghflg   # backend/supabase/.temp already holds this link locally
npx supabase migration list   # main's 3 migrations show as remote, gipar's as local only
npx supabase db push
```

**B. SQL Editor.**
1. Open Table Editor first and make sure `profiles`, `zones`, and `grid_cells` do not exist yet. The script fails on a project that already has them. main's tables (`map_areas`, `grid_restrictions`, …) are expected to exist and are not touched.
2. Open SQL Editor and create a new query.
3. Paste the whole `hosted_setup.sql` and run it. The script runs as one transaction, so either everything is created or nothing is.

This option does not record migration history. Before you use the CLI later, run this once:

```sh
npx supabase migration repair --status applied 20261016100000 20261016100100 20261016100200 20261016100300 20261016100400 20261016100500 20261016100600 20261016100700 20261016100800 20261016100900 20261016101000 20261016101100 20261016101200
```

## 2. Auth (from main)

Auth is Supabase native phone + password with SMS OTP (Twilio), used by `frontend/mobile` (`SupabaseAuthRepository`: `signUp(phone, password)`, `verifyOTP`, `signInWithPassword(phone, password)`).
- It is configured in the dashboard under Authentication → Sign In / Providers → Phone (enable, Twilio credentials, phone confirmation).
- **Do not run `npx supabase config push`**: `config.toml` is for local development and would overwrite those settings.
- On sign-up the trigger `handle_new_user` copies `auth.users.phone` (E.164 without `+`) into `profiles.phone`.

**Status: pending (no Twilio account yet).** Until then hosted phone sign-up cannot send an OTP; email logins (demo accounts) still work. Steps once the account exists:
1. Twilio Console: create a Messaging Service with a sender able to reach Indonesian numbers. Note the Account SID, Auth Token, and Messaging Service SID.
2. Supabase Dashboard → Authentication → Sign In / Providers → Phone: enable, provider Twilio, paste the three values, turn on phone confirmation, save.
3. Optional during the demo: under the same page, add test phone numbers with a fixed OTP (no SMS cost).
4. Check: sign up from the app with a real number, receive the SMS, `verifyOTP`, then `signInWithPassword(phone, password)`; `select phone from profiles` shows the number without `+`.

Locally, `config.toml` turns phone auth on with a dummy Twilio provider and fixed OTP `123456` for `6289900000001`…`003` (demo accounts) and `6289900000099` (fresh sign-up). No SMS is sent.

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

Or run everything (import if `grid_cells` is empty, refresh, cron check, the 4 smoke tests, and with `--demo` the demo seed) from `backend/` with `SUPABASE_DB_URL` in `backend/.env.local`:

```sh
bash scripts/hosted_load.sh --demo
```

The refresh step marks coral cells and publishes the first full heatmap. pg_cron then runs `private.daily_refresh()` every day at 00:10 WIB (job `heatmap-daily`) and processes manual refresh requests from the admin web every 10 seconds (job `heatmap-refresh-jobs`). Check both in Database → Cron.

## 4. Demo data (optional)

`../seed/demo.sql` adds persistent demo data for the app and dashboard. It is not a test, and its rows stay in the database. It needs the data import from section 3.

The scenarios use the Sendang Biru port (-8.43, 112.68):

| Account (password `Demo#2026`) | Scenario |
|---|---|
| `demo-baru@demo.reefish.app` / `6289900000002` | Boat filled, onboarding not done → onboarding → recommendations |
| `demo-aktif@demo.reefish.app` / `6289900000003` | 30 days of trips around `X102_Y156` → baseline and habitual |
| `demo-n01` … `demo-n20` (`62899000001xx`) | ~3 weeks on coral cells `X100..X102_Y152`: fatigue critical, auto-flag, never recommended, listed in the admin suggestions |
| `demo-admin@demo.reefish.app` / `6289900000001` (konservatif) | Owns the zone `Demo Karang Kuota` (restricted, 600 kg/month, ~85 % used) and the zone `Demo Rehab Pulih` (rehab, recovered → reopen suggestion, 1 violation) |

Run it with an explicit opt-in; without it the script refuses:

```sh
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -c "set reefish.allow_demo = 'on'" -f supabase/seed/demo.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/demo_reset.sql   # remove all demo data
```

In the SQL Editor, put `set reefish.allow_demo = 'on';` on the line above the contents of `demo.sql`.

Notes:
- Running it again replaces the previous demo data, and the dates follow today's date.
- `demo_reset` removes only `*@demo.reefish.app` accounts, `Demo %` zones, and their load on the heatmap.
- Email + password always works. Phone + password works locally (test OTP config) and on hosted once the phone provider is on (the numbers are already confirmed).

## 5. Check

Paste `../tests/fixed_grid.sql`, `../tests/nelayan.sql`, `../tests/zones_heatmap.sql`, and `../tests/layers.sql` into the SQL Editor (or use `scripts/hosted_load.sh`). It creates a test user, runs the whole RPC flow, and rolls everything back. A successful run ends with the notice `nelayan smoke test passed`.

## 6. Push notifications (FCM)

Zone changes queue rows in `push_outbox` (12.B.10). The Edge Function `push-dispatch` sends them: it claims rows with `api_internal_push_claim`, sends one FCM HTTP v1 message per device token, and reports with `api_internal_push_done` (failed rows retry up to 3 times, dead tokens are deleted).

Deploy the function (safe without the secret: it then answers `{"skipped": ...}` and leaves the queue alone):

```sh
npx supabase functions deploy push-dispatch
```

**Status: pending (no Firebase project yet).** Once it exists:
1. Firebase Console → Project settings → Service accounts → Generate new private key (JSON). Keep it out of git.
2. `npx supabase secrets set FCM_SERVICE_ACCOUNT="$(cat firebase-sa.json)"`
3. Schedule it every minute (SQL Editor, as postgres). Store the service role key in Vault first (Project Settings → API Keys → Legacy → `service_role`; the function compares it with its own `SUPABASE_SERVICE_ROLE_KEY`):

```sql
select vault.create_secret('<service_role key>', 'service_role_key');
select cron.schedule('push-dispatch', '* * * * *', $$
  select net.http_post(
    url := 'https://upyahsecuorqghcghflg.supabase.co/functions/v1/push-dispatch',
    headers := jsonb_build_object('Authorization', 'Bearer ' ||
      (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')))
$$);
```

4. Check: change a zone near a fisher with a registered device, then `select status, attempts from push_outbox order by id desc limit 5` shows `sent`.

The Flutter app also needs `google-services.json` from the same Firebase project and must call `api_register_device` with its token.

## 7. Queries per endpoint

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
| Saran sistem (restrict + reopen) | `select api_admin_suggestions();`, `select api_admin_suggestions('reopen');` |
| me (admin) | `select api_me();` returns role `konservatif`, `next_step` `done` |
| automaticFlagToRestricted (service_role / postgres only) | `select api_internal_auto_flag(null, true);` |

From Next.js the call is the same, for example `supabase.rpc('api_admin_create_zone', { p: {...} })`.

### Auth (native, from main)

Flutter: `supabase.auth.signUp(phone: '+6281234567890', password: ...)`, then `verifyOTP(type: OtpType.sms, phone, token)`. Later logins use `signInWithPassword(phone: ..., password: ...)`.
Send `session.accessToken` as `Authorization: Bearer` to the Go service.

### Promote a konservatif account (SQL Editor, as postgres)

```sql
update profiles set role = 'konservatif' where phone = '6281234567890';
```

### Go service (computation, not Supabase)

`GET /api/v1/recommendations` and `GET /api/v1/weather` with `Authorization: Bearer <access_token>`. Behind the scenes these call `api_rec_context`, `api_save_recommendations` and `api_in_pilot`.
