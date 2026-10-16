# Backend

Supabase adalah arah rekomendasi awal. Direktori ini menjadi rumah migrasi, fungsi, dan pengujian backend. Kerangka ini tidak mewajibkan server NestJS terpisah.

Supabase menangani auth, data cluster ML, dan zona konservasi. Service Go kecil (`api/`, entry `api/cmd/api`) menghitung rute pergi-pulang dengan estimasi BBM.
Spesifikasi rute: `../docs/spesifikasi-backend-rute-nelayan-golang-gin.md`. Kontrak API: `../contracts/route-api.openapi.yaml`.

Kontrak kanonis lintas domain berada di `contracts/`. Aturan akses dan validasi ditegakkan di backend, bukan hanya di UI.

## Struktur

```
api/                      service Go (module nelayan-route): go.mod, .env.example
  cmd/api/                wiring: config, adapter -> use case, HTTP server
  internal/
  domain/                 aturan murni, tanpa I/O
    physics/              vektor arus/angin, STW-SOG, kurva BBM, cadangan
    routing/              grid 500 m, poligon zona, Dijkstra
    environment/          snapshot kondisi laut (kontrak satuan & arah)
  usecase/planroute/      request, validasi, orkestrasi, hasil; port (interface)
  adapter/
    http/                 Gin: decode JSON, header auth, mapping error -> status
    supabase/             repo grid & zona via PostgREST (JWT user, RLS)
    openmeteo/            provider angin/arus/gelombang
    auth/                 token user lewat context
supabase/                 struktur sama dengan branch main
  migrations/             skema, RLS, RPC (berurutan; grid lock main + migrasi gipar)
  functions/              Edge Functions (belum ada yang aktif)
  tests/                  smoke test SQL (fixed_grid.sql dari main + test gipar)
  archive/                desain grid dinamis yang dibatalkan (dari main)
  setup/                  panduan hosted + hosted_setup.sql
scripts/                  konversi output ML GeoJSON -> CSV untuk import, check_sql.py (cek sintaks SQL)
```

CI `.github/workflows/backend.yml` menjalankan gofmt, `go vet`, dan `go test` (termasuk vektor uji grid) serta cek sintaks SQL. Smoke test SQL tidak masuk CI karena butuh data ML yang tidak ada di git; jalankan secara lokal (`supabase/setup/README.md`).

Arah dependency: `adapter -> usecase -> domain`. Domain dan use case tidak mengimpor Gin, HTTP, atau SQL.

## Menjalankan

1. `npx supabase link --project-ref <ref>` lalu `npx supabase db push`.
2. Import data. Output model ML (`clusters_*.geojson` + `metadata.json`) diletakkan di `../machine-learning/data/geojson/`; folder ini diabaikan git.
   ```
   python scripts/geojson_to_csv.py ../machine-learning/data/geojson out
   psql "$SUPABASE_DB_URL" -c "\copy grid_cells(grid_id, geom) from 'out/grid_cells.csv' csv header"
   psql "$SUPABASE_DB_URL" -c "\copy cluster_predictions from 'out/cluster_predictions.csv' csv header"
   ```
3. Jadikan akun konservatif: `update profiles set role = 'konservatif' where id = '<uuid>';`
4. Service Go: `cd api`, export env sesuai `api/.env.example` (tidak dibaca otomatis), lalu `go run ./cmd/api`.
5. Test: `cd api && go test ./...`

## Auth

Auth mengikuti branch main: Supabase Auth bawaan dengan no telp + password + OTP SMS (Twilio), dipanggil langsung dari `frontend/mobile`.
- Trigger `handle_new_user` menyalin `auth.users.phone` (E.164 tanpa `+`) ke `profiles.phone`.
- Setelan auth hosted diatur di dashboard. `config.toml` hanya untuk lokal.

Deploy (setelah `npx supabase login` dan `npx supabase link --project-ref upyahsecuorqghcghflg`):
```
npx supabase db push
# jangan jalankan `config push`: setelan auth hosted (phone + Twilio) diatur di dashboard
```

## API

| Sumber | Endpoint | Untuk |
|---|---|---|
| Supabase Auth | `signUp` / `verifyOTP` / `signInWithPassword` dengan phone | Daftar dan login (dari main) |
| Supabase RPC | `get_grid_lock_snapshot`, `set_grid_lock`, `validate_fishing_grid_selection` | Grid lock dari main (`../contracts/grid-locks.md`) |
| Supabase RPC | `get_fishing_spots(p_period, p_min_level)` | Peta spot nelayan; titik di zona `rehab` atau zona `restricted` yang kuotanya habis dibuang |
| Supabase RPC | `get_clusters(p_period, p_min_level)` | Peta cluster di dashboard konservatif |
| Supabase RPC | `api_grid_meta`, `api_sea_mask`, `api_zones`, `api_heatmap`, `api_heatmap_version`, `api_heatmap_changes`, `api_sync_seen`, `api_register_device`, `api_unregister_device` | Peta bersama (kedua role), sinkron, perangkat push |
| Supabase RPC | `api_layers(p_period, ...)`, `api_habitat()` | Layer ML per periode (level, potensi, suhu, klorofil, kedalaman, potensi_ikan) dan polygon coral/mangrove |
| Supabase RPC | `api_admin_*` (zona, flag, saran restrict/reopen, riwayat, statistik, detail grid, refresh heatmap), `api_internal_auto_flag` (service_role) | Dashboard konservatif (AGENTS.md 12.A) |
| (dipakai ulang admin) | `api_me`, RPC peta, `api_layers`, `api_habitat`, Go `/api/v1/weather`, `/api/v1/weather/area`, `/v1/routes` | Endpoint yang sama dengan nelayan; hanya rekomendasi, kapal, dan trip yang khusus nelayan |
| Supabase RPC | `api_me`, `api_create_boat`, `api_update_boat`, `api_post_trip`, `api_list_trips`, `api_trip_detail`, `api_mobile_config` | Data nelayan (profil, kapal, trip, riwayat); dipanggil langsung dari Flutter |
| Supabase RPC | `api_rec_context`, `api_save_recommendations`, `api_in_pilot` | Dipakai service Go untuk rekomendasi dan cuaca |
| Go service | `POST /v1/routes` | Rute + estimasi BBM, header `Authorization: Bearer <JWT Supabase>` |
| Go service | `GET /api/v1/recommendations`, `GET /api/v1/weather`, `GET /api/v1/weather/area` | Rekomendasi 4 tipe (heuristik + prediksi BBM), cuaca titik, dan cuaca area |

Aturan pembagian: yang bisa dikerjakan Supabase tetap di Supabase. Perhitungan (ranking, prediksi BBM, cuaca) ada di Go.
Kontrak: `../contracts/nelayan-api.openapi.yaml` dan `../contracts/map-zones-api.openapi.yaml`.
Smoke test SQL setelah `db push` dan import grid: `supabase/tests/nelayan.sql` dan `supabase/tests/zones_heatmap.sql`.
Heatmap (fatigue, tekanan, CPUE, auto-flag) dihitung ulang di SQL setiap trip selesai, dan harian lewat pg_cron `heatmap-daily` (00:10 WIB).

Detail request/response: `../contracts/route-api.openapi.yaml`.
