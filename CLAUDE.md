# CLAUDE.md

Reefish: coral-reef-friendly fishing. Two roles:
- `nelayan` (Flutter mobile) sees fishing spots and route + fuel estimates.
- `konservatif` (Next.js web) groups grid cells into zones with status `restricted` (quota) or `rehab` (closed).

The ML model flags vulnerable grid cells.

## Repo map

```
backend/            same layout as main: README + supabase/, plus the Go service and import scripts
  api/              Go service (module nelayan-route): cmd/api wiring, internal/ clean architecture
  supabase/         migrations/ (ordered), functions/, tests/, archive/ (main), setup/, config.toml
  scripts/          ML GeoJSON -> CSV import
frontend/mobile/    Flutter (nelayan)
frontend/web/       Next.js (konservatif)
machine-learning/   notebooks, src, models (no weights/data in git)
contracts/          canonical cross-domain contracts (OpenAPI)
docs/               specs
```

## Sources of truth (highest first)

1. `contracts/*.openapi.yaml`
2. The code.
3. `docs/spesifikasi-backend-rute-nelayan-golang-gin.md`: route and fuel calculation.
4. `docs/AGENTS.md` (v0.8): product and domain reference (grid IDs, fatigue, zones, recommendations, ML contract). Its architecture parts are outdated wherever they conflict with this file:
   - section 1.1 (no Supabase Auth/PostgREST/Edge Functions)
   - section 3 (roles `fisher`/`admin`)
   - section 12.A.3 (custom Go auth)

   Do not read it whole: it is ~2500 lines. Grep for the section you need.
5. `docs/frontend/panduan-implementasi-flutter-peta-laut-v2.md`: map layers, data audit, and grid definition. It supersedes AGENTS.md 5.1 for grid IDs.

## Grid

All layers and `grid_cells` share one grid:
- EPSG:32749, 500 m cells, lower-left origin (637500, 8988000).
- `grid_x` 1..187 runs east and `grid_y` 1..177 runs north; 31,354 cells have data.
- Backend ID: `X{grid_x:03}_Y{grid_y:03}`.
- Lookup: `grid_x = floor((E − 637500)/500) + 1`, `grid_y = floor((N − 8988000)/500) + 1`.

Data layout is described in `machine-learning/data/README.md`. The data is gitignored.

## Architecture (current)

- **Supabase** (project `upyahsecuorqghcghflg`):
  - Postgres + PostGIS, Auth, RLS.
  - PostgREST RPC: `api_*` for nelayan data, map, heatmap, and admin (zones, flags, stats); see `contracts/`.
  - Edge Functions.
- **Go Gin** `POST /v1/routes`:
  - Dijkstra on a 500 m grid that avoids closed zones (`rehab`, or a quota used up), then a round-trip fuel estimate.
  - Authenticates with the user's Supabase JWT and reads data through RLS.
- **Weather**: Open-Meteo at a single point. Check units; never treat null as zero.
- **Split rule:** anything Supabase can do stays in Supabase (RPC, RLS, Edge Functions). Computation goes to Go: route search, fuel prediction, recommendation ranking, weather.
  - Example: the nelayan API (`contracts/nelayan-api.openapi.yaml`). Data endpoints are `api_*` RPCs in `0006_nelayan.sql`; Go serves `/api/v1/recommendations`, `/api/v1/weather`, and `/api/v1/weather/area`.
- **Zones and heatmap** (`0007_zones_heatmap.sql`, `contracts/map-zones-api.openapi.yaml`): a zone is a set of grid cells (`zone_grids`) per AGENTS.md 6 and 12.A, with `ZoneEntry`, quota, version, and history.
  - Fatigue, pressure, CPUE, and auto-flag are computed in SQL and published as `heatmap_cells` + `heatmap_version`.
  - Recomputation runs after each trip and daily via pg_cron.
- **ML and habitat layers** (`0008_ml_layers.sql`):
  - `api_layers(period)` returns per-cell `level`, `potential_score`, `sst`, `chlor_a`, `depth_m` (`cluster_predictions`) plus `potensi_ikan` (`grid_layers`).
  - `api_habitat()` returns coral and mangrove polygons.

## Auth

**Target:** register and login with phone number + password. At register, verify the number with a **Twilio OTP / verification code**. Password rule: at least 8 characters, including an uppercase letter, a digit, and a symbol.

**Current state:** `supabase/functions/auth-register` and `auth-login` have no OTP. They map the phone number to a synthetic email `62…@phone.reefish.app`. Rework them to use the Supabase Phone provider with Twilio, then update `contracts/auth-api.openapi.yaml`.

Phone numbers are normalised to `62XXXXXXXXXX` in `supabase/functions/_shared/auth.ts`.

## Commands

```
cd backend/api
go test ./...                              # gofmt -w after editing Go
go run ./cmd/api                           # env per .env.example (not auto-loaded)
cd backend
npx deno test supabase/functions/_shared/  # Edge Function rules
npx supabase db push                       # migrations
npx supabase functions deploy <name>
```

## Rules

- Never commit datasets, user data, credentials, `.env*`, model weights, checkpoints, or build output. `*.geojson` and `*.csv` are gitignored.
- A cross-domain change updates `contracts/` first.
- A backend change ships with a migration and a test.
- Do not claim a check passed unless it ran.
- JSON uses `snake_case`.
- Errors use the shape `{ "error": { "code", "message", "details"? } }`.
- Coordinates use EPSG:4326. In GeoJSON the order is `[lon, lat]`.
- User-facing text is in Bahasa Indonesia. Code, comments, and commits are in English.
